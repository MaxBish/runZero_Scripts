## Ubiquiti Site Manager Custom Integration

load("runzero.types", "ImportAsset", "NetworkInterface")
load("json", json_decode="decode")
load("http", http_get="get")
load("net", "ip_address")

# You should set this to the base URL of your Ubiquiti Site Manager instance.
# For example, "https://example.ui.com"
UI_API_BASE_URL = ""
HOSTS_ENDPOINT = "/v1/hosts"

def get_hosts(api_token):
    """
    Retrieves all hosts from the Ubiquiti Site Manager API using pagination.
    """
    headers = {
        "Authorization": "Bearer {}".format(api_token),
        "Accept": "application/json"
    }

    all_hosts = []
    hasNextPage = True
    
    while hasNextPage:
        url = {}{}.format(UI_API_BASE_URL, HOSTS_ENDPOINT)
        
        print("Fetching hosts from: {}".format(url))
        response = http_get(url=url, headers=headers)
        
        if response.status_code != 200:
            print("Failed to fetch hosts. Status code: {}".format(response.status_code))
            print("Response body: {}".format(response.body))
            return None
        
        hosts_data = json_decode(response.body).get("data", [])
            
        all_hosts.extend(hosts_data)

    print("Successfully retrieved a total of {} hosts.".format(len(all_hosts)))
    return all_hosts

def build_network_interface(host):
    """
    Safely creates a NetworkInterface object from host data.
    """
    ip_addrs = host.get('ip_address', [])
    mac_addrs = host.get("userData", {}).get("consoleGroupMembers",{}).get("mac", "")

    ipv4s = []
    ipv6s = []
    
    if type(ip_addrs) == type(""):
        ip_addrs = [ip_addrs]
        
    for ip in ip_addrs:
        if ip:
            ip_obj = ip_address(ip)
            if ip_obj and ip_obj.version == 4:
                ipv4s.append(ip_obj)
            elif ip_obj and ip_obj.version == 6:
                ipv6s.append(ip_obj)
    
    if mac_addrs:
        return NetworkInterface(macAddress=mac_addrs, ipv4Addresses=ipv4s, ipv6Addresses=ipv6s)
    elif ipv4s or ipv6s:
        return NetworkInterface(macAddress=None, ipv4Addresses=ipv4s, ipv6Addresses=ipv6s)
    
    return None

def build_assets(hosts):
    """
    Converts a list of Ubiquiti host dictionaries into ImportAsset objects.
    """
    assets = []
    for host in hosts:
        print(host)
        asset_id = host.get("id", "")
        if not asset_id:
            continue
            
        hostname = host.get("hostname", "")
        
        net_iface = build_network_interface(host)
        if not net_iface:
            continue
            
        assets.append(
            ImportAsset(
                id=str(asset_id),
                hostnames=[hostname] if hostname else [],
                networkInterfaces=[net_iface],
                os=host.get("os", ""),
                osVersion=host.get("os_version", ""),
                customAttributes={
                    "ui_manufacturer": host.get("manufacturer", ""),
                    "ui_model": host.get("model", ""),
                    "ui_tags": host.get("tags", []),
                },
                tags=["ubiquiti", "site-manager"]
            )
        )
    return assets

def main(**kwargs):
    """
    Main entry point for the Ubiquiti Site Manager integration.
    """
    # Get the API token from runZero credentials
    api_token = kwargs.get('access_secret')
    
    if not api_token:
        print("Error: Ubiquiti API token (access_secret) not provided.")
        return []
        
    hosts = get_hosts(api_token)
    
    if not hosts:
        print("Error: Failed to retrieve hosts from Ubiquiti Site Manager.")
        return []
    
    return build_assets(hosts)