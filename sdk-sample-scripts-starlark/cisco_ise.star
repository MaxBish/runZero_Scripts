## Cisco ISE integration
 
## Loading dependencies
load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_post='post', http_get='get', 'url_encode')
 
## Cisco ISE API URL
CISCO_ISE_API_URL = "https://XXXXXXXXXXXXXX:443/api/v1/endpoint"
 
 
def get_ise_endpoints(username,password):
    endpoints = []
    hasNextPage = True
    page = 1
    page_size = 100
 
    headers = {
        'accept': "application/json",
        'authorization': "Basic "+password,
        'content-type': "application/json",
    }
 
    while hasNextPage:
        params = {"page": page,
            "size": page_size
        }
 
        data = http_get(CISCO_ISE_API_URL,
            headers=headers,
            params=params
            )
        if data.status_code != 200:
            print("unsuccessful request", "url = {}".format(CISCO_ISE_API_URL), data.status_code, data.message)
            print("")
            print(data)
            print("")
            return endpoints
        inventory = json_decode(data.body)
        if not inventory:
            hasNextPage = False
        else:
            endpoints.extend(inventory)
            print(inventory)
            page += 1
    return endpoints
 
def build_assets(inventory):
    assets = []
    for item in inventory:
        asset = build_asset(item)
        if asset:
            assets.append(asset)
 
    return assets
 
def build_asset(item):
    asset_id = item.get("id", None)
    if not asset_id:
        return None
 
    device_type = item.get("deviceType", None)
    groupId = item.get("groupId", None)
    ipAddress = item.get("ipAddress", None)
    mac = item.get("mac", None)
    name = item.get("name", None)
 
    ips = [ipAddress]
    networks = []
    for m in mac:
        network = asset_networks(ips=ips, mac=m)
        networks.append(network)
 
    return ImportAsset(
        id=asset_id,
        networkInterfaces=networks,
        hostnames=name,
        customAttributes={
            "groupId": groupId,
        }
    )
 
def asset_networks(ips,mac):
    ip4s=[]
    ip6s=[]
 
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
    return NetworkInterface(macAddress=mac,ipv4Addresses=ip4s, ipv6Addresses=ip6s)
 
 
def main(*args,**kwargs):
    username = kwargs['access_key']
    password = kwargs['access_secret']
 
    cisco_ise_endpoints = get_ise_endpoints(username,password)
 
    if not cisco_ise_endpoints:
        print("Got nothing from Cisco ISE")
        return None
 
    assets = build_assets(cisco_ise_endpoints)
 
    if not assets:
        print("no assets")
 
    return assets