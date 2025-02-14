## Cortex XDR - Starlark script 

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_post='post', http_get='get', 'url_encode')


CORTEX_URL = 'https://api-{FQDN}/public_api/v1/endpoints/get_endpoints'


def get_cortex_inventory(cortex_api_key_id, cortex_api_key):
    hasNextPage = True
    endpoints = []
    payload = {}
    search_to = 100
    search_from = 0

    ## Generate headers
    headers = {
        "x-xdr-auth-id": str(cortex_api_key_id),
        "Authorization": cortex_api_key,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    while hasNextPage:
        params={"search_from": search_from, "search_to": search_to}

        resp = http_post(CORTEX_URL, headers=headers, body=bytes(json_encode(params)))
        if resp.status_code != 200:
            print("unsuccessful request", "url={}".format(url), resp.status_code, resp.message)
            return endpoints

        inventory = json_decode(resp.body)
        results = inventory.get('reply', None)
        if not results:
            hasNextPage = False
            continue

        endpoints.extend(results)
        search_from += 100
        search_to += 100

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
    asset_id = item.get('agent_id', None)
    if not asset_id:
        return None

    ip_address = item.get('ip', None)
    agent_status = item.get('agent_status', None)
    operational_status = item.get('operational_status', None)
    endpoint_name = item.get('host_name', None)
    agent_type = item.get('agent_type', None)

    # create network interfaces
    ips = [ip_address]
    networks = []
    network = asset_networks(ips=ips, mac=m)
    networks.append(network)

    return ImportAsset(
        id=asset_id,
        networkInterfaces=networks,
        hostnames=endpoint_name,
        customAttributes={
            "operational_status": operational_status,
            "agent_status": agent_status,
            "agent_type": agent_type,
        }
    )

def build_assets(inventory):
    assets = []
    for item in inventory:
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