"""runZero inbound PoC for Zscaler Analytics GraphQL ingestion."""

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('http', http_post='post', 'url_encode')

# Zscaler Analytics uses GraphQL via OneAPI and OAuth2 client credentials via ZIdentity.
ZSCALER_TOKEN_URL = 'https://<UPDATE_ME>.zslogin.net/oauth2/v1/token'
ZSCALER_GRAPHQL_URL = 'https://api.zsapi.net/zins/graphql'
ZSCALER_AUDIENCE = 'https://api.zscaler.com'

# Edit this query to target domains/fields that return endpoint-level identities.
# This default is intentionally conservative and may need tenant-specific updates.
ZSCALER_GRAPHQL_QUERY = """
query AssetInventory($limit: Int!) {
    IOT {
        device_inventory {
            entries(limit: $limit) {
                id
                name
                hostname
                fqdn
                ip
                ip_address
                ipv4
                ipv6
                mac
                mac_address
                os
                os_version
                user
            }
        }
    }
}
"""

GRAPHQL_LIMIT = 1000
SOURCE_NAME = 'zscaler-analytics'


def is_digits(text):
    """Return True when input is only numeric characters."""
    if text == None:
        return False
    if text == '':
        return False
    for char in text:
        if char < '0' or char > '9':
            return False
    return True


def is_valid_ipv4(value):
    """Validate an IPv4 address string."""
    if value == None:
        return False
    ip = str(value).strip()
    parts = ip.split('.')
    if len(parts) != 4:
        return False
    for part in parts:
        if not is_digits(part):
            return False
        number = int(part)
        if number < 0 or number > 255:
            return False
    return True


def is_likely_ipv6(value):
    """Best-effort IPv6 detection without strict parser dependencies."""
    if value == None:
        return False
    ip = str(value).strip().lower()
    if ':' not in ip:
        return False
    if len(ip) > 39:
        return False
    allowed = '0123456789abcdef:'
    for char in ip:
        if char not in allowed:
            return False
    return True


def get_first_string(item, keys, default_value=''):
    """Return first non-empty string value found for candidate keys."""
    for key in keys:
        value = item.get(key, None)
        if value != None and str(value).strip() != '':
            return str(value).strip()
    return default_value


def as_list(value):
    """Normalize scalar/list values into list form."""
    if value == None:
        return []
    value_type = type(value)
    if value_type == 'list':
        return value
    if value_type == 'string':
        return [value]
    return []


def collect_ip_candidates(item):
    """Collect and normalize IPv4/IPv6 values from flexible payload shapes."""
    raw_ips = []

    for key in ['ip', 'ipAddress', 'ipv4', 'ipv6', 'primaryIp', 'publicIp', 'privateIp']:
        value = item.get(key, None)
        for ip in as_list(value):
            raw_ips.append(str(ip).strip())

    addresses = item.get('addresses', None)
    if type(addresses) == 'list':
        for address_item in addresses:
            if type(address_item) == 'dict':
                for nested_key in ['ip', 'ipAddress', 'address', 'value']:
                    nested_value = address_item.get(nested_key, None)
                    if nested_value != None:
                        raw_ips.append(str(nested_value).strip())
            elif address_item != None:
                raw_ips.append(str(address_item).strip())

    ip4s = []
    ip6s = []
    seen = {}

    for candidate in raw_ips:
        if candidate == '':
            continue
        if candidate in seen:
            continue
        seen[candidate] = True

        if is_valid_ipv4(candidate):
            ip4s.append(candidate)
        elif is_likely_ipv6(candidate):
            ip6s.append(candidate)

    return ip4s, ip6s


def normalize_mac(raw_mac):
    """Normalize MAC address delimiters/casing."""
    if raw_mac == None:
        return ''
    mac = str(raw_mac).strip().lower()
    if mac == '':
        return ''
    mac = mac.replace('-', ':')
    return mac


def build_network_interface(item):
    """Build runZero NetworkInterface from normalized fields."""
    ip4s, ip6s = collect_ip_candidates(item)

    mac = get_first_string(item, ['macAddress', 'mac', 'mac_address', 'primaryMac'])
    if mac == '':
        macs = as_list(item.get('macAddresses', None)) + as_list(item.get('mac_addresses', None))
        if len(macs) > 0:
            mac = str(macs[0]).strip()

    mac = normalize_mac(mac)

    if mac != '':
        return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)

    return NetworkInterface(ipv4Addresses=ip4s, ipv6Addresses=ip6s)


def is_asset_like_record(item):
    """Heuristic filter for GraphQL objects that likely represent endpoints/assets."""
    if type(item) != 'dict':
        return False

    keys = [
        'id', 'deviceId', 'endpointId', 'assetId', 'machineId',
        'hostname', 'hostName', 'fqdn', 'name', 'deviceName',
        'ip', 'ipAddress', 'ipv4', 'ipv6',
        'mac', 'macAddress', 'mac_address',
        'os', 'osName', 'platform', 'platformName',
    ]
    for key in keys:
        if item.get(key, None) != None and str(item.get(key)).strip() != '':
            return True
    return False


def extract_asset_candidate_records(value):
    """Recursively collect candidate endpoint objects from GraphQL response data."""
    records = []

    if type(value) == 'list':
        for entry in value:
            nested = extract_asset_candidate_records(entry)
            for item in nested:
                records.append(item)
        return records

    if type(value) != 'dict':
        return records

    if is_asset_like_record(value):
        records.append(value)

    for _, nested_value in value.items():
        nested = extract_asset_candidate_records(nested_value)
        for item in nested:
            records.append(item)

    return records


def request_access_token(client_id, client_secret):
    """Request OAuth access token from ZIdentity using client credentials flow."""
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json'
    }
    body = bytes(url_encode({
        'grant_type': 'client_credentials',
        'client_id': client_id,
        'client_secret': client_secret,
        'audience': ZSCALER_AUDIENCE
    }))

    response = http_post(ZSCALER_TOKEN_URL, headers=headers, body=body)
    if not response:
        print('Token request failed: no response from server')
        return ''

    if response.status_code != 200:
        print('Token request failed with status {}'.format(response.status_code))
        return ''

    payload = json_decode(response.body)
    token = payload.get('access_token', '')
    if token == '':
        print('Token request failed: access_token missing in response')
        return ''

    return str(token)


def get_bearer_token(access_key, access_secret):
    """Obtain a bearer token, or treat access_secret as a direct bearer token fallback."""
    # If access_secret already appears to be a bearer token, use it directly.
    if access_secret != None and str(access_secret).strip() != '' and str(access_key).strip() == '':
        return str(access_secret).strip()

    return request_access_token(str(access_key).strip(), str(access_secret).strip())


def run_graphql_query(token, query, variables):
    """Execute GraphQL query against Zscaler Analytics endpoint."""
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer {}'.format(token)
    }
    body = bytes(json_encode({'query': query, 'variables': variables}))

    response = http_post(ZSCALER_GRAPHQL_URL, headers=headers, body=body)
    if not response:
        print('GraphQL request failed: no response')
        return None

    if response.status_code != 200:
        print('GraphQL request failed with status {}'.format(response.status_code))
        return None

    payload = json_decode(response.body)
    if payload.get('errors', None):
        print('GraphQL returned errors: {}'.format(str(payload.get('errors'))[:500]))
        return None

    return payload.get('data', {})


def deterministic_asset_id(item, hostnames, ip4s, ip6s):
    """Create a stable asset ID using provider ID or deterministic fallback."""
    raw_id = get_first_string(item, ['id', 'deviceId', 'endpointId', 'assetId', 'machineId'])
    if raw_id != '':
        return '{}:{}'.format(SOURCE_NAME, raw_id)

    key_parts = []
    if len(hostnames) > 0:
        key_parts.append(hostnames[0])
    if len(ip4s) > 0:
        key_parts.append(ip4s[0])
    if len(ip6s) > 0:
        key_parts.append(ip6s[0])

    if len(key_parts) == 0:
        return ''

    fallback = '|'.join(key_parts).lower().replace(' ', '_')
    if len(fallback) > 200:
        fallback = fallback[:200]
    return '{}:fallback:{}'.format(SOURCE_NAME, fallback)


def map_item_to_asset(item):
    """Map one source record into runZero ImportAsset."""
    hostname = get_first_string(item, ['hostname', 'hostName', 'name', 'deviceName', 'fqdn'])
    hostnames = []
    if hostname != '':
        hostnames.append(hostname)

    netif = build_network_interface(item)

    ip4s, ip6s = collect_ip_candidates(item)
    asset_id = deterministic_asset_id(item, hostnames, ip4s, ip6s)
    if asset_id == '':
        return None

    if len(hostnames) == 0 and len(ip4s) == 0 and len(ip6s) == 0:
        return None

    os_name = get_first_string(item, ['os', 'osName', 'platform', 'platformName'])
    os_version = get_first_string(item, ['osVersion', 'platformVersion', 'version'])

    custom_attrs = {
        'source': SOURCE_NAME,
        'rawStatus': get_first_string(item, ['status', 'state', 'healthStatus']),
        'rawUser': get_first_string(item, ['user', 'username', 'userName'])
    }

    return ImportAsset(
        id=asset_id,
        hostnames=hostnames,
        networkInterfaces=[netif],
        os=os_name,
        osVersion=os_version,
        customAttributes=custom_attrs,
        tags=['source:zscaler', 'integration:poc']
    )


def build_assets(raw_items):
    """Map raw records to deduplicated runZero assets."""
    assets = []
    seen = {}

    for item in raw_items:
        if type(item) != 'dict':
            continue

        asset = map_item_to_asset(item)
        if asset == None:
            continue

        if asset.id in seen:
            continue

        seen[asset.id] = True
        assets.append(asset)

    return assets


def main(*args, **kwargs):
    """Entrypoint for runZero custom integration task."""
    # Credentials are supplied by runZero Custom Script Secret.
    access_key = kwargs.get('access_key', '')
    access_secret = kwargs.get('access_secret', '')

    token = get_bearer_token(access_key, access_secret)
    if token == '':
        print('Unable to authenticate to Zscaler API.')
        return []

    variables = {
        'limit': GRAPHQL_LIMIT
    }

    data = run_graphql_query(token, ZSCALER_GRAPHQL_QUERY, variables)
    if data == None:
        return []

    raw_items = extract_asset_candidate_records(data)
    assets = build_assets(raw_items)

    print('Prepared {} assets for import from {} candidate records.'.format(len(assets), len(raw_items)))
    return assets
