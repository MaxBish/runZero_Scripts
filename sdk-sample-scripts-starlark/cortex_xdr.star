load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_post='post', http_get='get', 'url_encode')


CORTEX_URL = 'https://api-{FQDN}/'


def get_cortex_inventory(cortex_api_key_id, cortex_api_key):
    hasNextPage = True
    endpoints = []
    post_data = {}
    page_size = 100
    page = 0

    ## Generate a 64 bytes random string
    nonce = "".join([secrets.choice(string.ascii_letters + string.digits) for _ in range(64)])

    timestamp = int(datetime.now(timezone.utc).time()) * 1000

    auth_key = "%s%s%s" % (cortex_api_key, nonce, timestamp)

    auth_key = auth_key.encode("utf-8")

    api_key_hash = hashlib.sha256(auth_key).hexdigest()

    ## Generate headers
    headers = {
        "x-xdr-timestamp": str(timestamp),
        "x-xdr-nonce": nonce,
        "x-xdr-auth-id": str(cortex_api_key_id),
        "Authorization": api_key_hash
    }

    url = CORTEX_URL_URL + 'public_api/v1/endpoints/get_endpoints'

    while hasNextPage:
        params={"page": page, "page-size": page_size}
        resp = http_post(url=url, headers=headers, params=params)
        if resp.status_code != 200:
            print("unsuccessful request", "url={}".format(url), resp.status_code)
            return endpoints

        inventory = json_decode(resp.body)
        results = inventory.get('results', None)
        if not results:
            hasNextPage = False
            continue

        endpoints.extend(results)
        page += 1

    return endpoints


def asset_networks(ips, mac):
    ip4s = []
    ip6s = []
    for ip in ips[:99]:
        ip_addr = ip_address(ip)
        if ip_addr.version == 4:
            ip4s.append(ip_addr)
        elif ip_addr.version == 6:
            ip6s.append(ip_addr)
        else:
            continue

    if not mac:
        return NetworkInterface(ipv4Addresses=ip4s, ipv6Addresses=ip6s)

    return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)


def build_asset(item):
    asset_id = item.get('id', None)
    if not asset_id:
        return None

    operational_status = item.get("operational_status", None)
    agent_status = item.get("endpoint_status", None)
    agent_type = item.get("endpoint_type", None)
    groups = ";".join(item.get("group_name", None))
    assigned_prevention_policy = item.get("assigned_prevention_policy", None)
    assigned_extensions_policy = item.get("assigned_extensions_policy", None)
    endpoint_version = item.get("endpoint_version", None)
    mac_address = item.get("mac_address", None)
    ip_address = item.get("ip", None)

    # create network interfaces
    ips = [ip_address]
    networks = []
    for m in mac_address:
        network = asset_networks(ips=ips, mac=m)
        networks.append(network)

    return ImportAsset(
        id=asset_id,
        networkInterfaces=networks,
        os=item.get("operating_system", None),
        osVersion=item.get("os_version", None),
        hostnames=item.get("endpoint_name", None),
        customAttributes={
            "operational_status": operational_status,
            "agent_status": agent_status,
            "agent_type": agent_type,
            "groups": groups,
            "assigned_prevention_policy": assigned_prevention_policy,
            "assigned_extensions_policy": assigned_extensions_policy,
            "endpoint_version": endpoint_version,
        }
    )


def build_assets(inventory):
    assets = []
    for item in inventory:
        asset_info = item.get("node",{})
        asset = build_asset(asset_info)
        if asset:
            assets.append(asset)

    return assets


def main(*args, **kwargs):
    cortex_api_key_id = kwargs['access_key']
    cortex_api_key = kwargs['access_secret']

    cortex_endpoints = get_cortex_inventory(cortex_api_key_id, cortex_api_key)
    if not cortex_endpoints:
        print("got nothing from cortex")
        return None

    assets = build_assets(cortex_endpoints)
    if not assets:
        print("no assets")

    return assets
