## AUTOMOX INTEGRATION

## Loading dependencies
load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_post='post', http_get='get', 'url_encode')

## Automox API URL
AUTOMOX_URL = 'https://console.automox.com/api/servers'

def get_endpoints(automox_token):
    query = {
        "limit": "500",
        "page": "0"
    }

    endpoints = []
    hasNextPage = True
    headers = {
        "Authorization": f"Bearer {automox_token}"
    }
    while hasNextPage:
        data = http_post(
            AUTOMOX_URL,
            headers=headers,
            params=query,
        )

        json_data = json_decode(data.body)
        new_endpoints = json_data.get("data",{}).get("endpoints", {}).get("edges", [])
        endpoints.extend(new_endpoints)

        hasNextPage = json_data.get("data", {}).get("endpoints", {}).get("pageInfo", {}).get("hasNextPage", False)

    return endpoints

def build_assets(inventory):
    assets = []
    for item in inventory:
        asset_info = item.get("node", {})
        asset = build_asset(asset_info)
        if asset:
            assets.append(asset)

    return assets

def build_asset(item):
    asset_id = item.get("id", None)
    if not asset_id:
        return None

    os_version = item.get("os_version", None)
    os_name = item.get("os_name", None)
    os_family = item.get("os_family", None)
    agent_version = item.get("agent_version", None)
    compliant = item.get("compliant", None)
    serial_number = item.get("serial_number", None)

      ## handle IPs
    ips = []
    ips.append(endpoint['ip_addrs'])
    ips.append(endpoint['ip_addrs_private'])
    networks = []
    for m in mac_address:
        network = asset_networks(ips=ips, mac=m)
        networks.append(network)

    return ImportAsset(
         id=asset_id,
         networkInterfaces=networks
         hostnames=item.get("name", None),
         os_version=os_version,
         customAttributes={
            "os_name": os_name,
            "os_family": os_family,
            "agent_version": agent_version,
            "compliant": compliant,
            "serial_number": serial_number,
         }
      )

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
        return NetworkInterface(ipv4Addresses=ip4s,ipv6Addresses=ip6s)
    return NetworkInterface(macAddress = mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)


def main(*args,**kwargs):
    automox_token = kwargs['access_secret']

    automox_endpoints = get_endpoints(automox_token)

    if not automox_endpoints:
        print("nothing from Automox")
        return None

    assets = build_assets(automox_endpoints)

    if not assets:
        print("no assets")
    
    return assets
