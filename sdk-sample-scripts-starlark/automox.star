## Automox!

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_get='get', 'url_encode')
load('uuid', 'new_uuid')

AUTOMOX_API_URL = "https://console.automox.com/api/servers"

def get_automox_devices(api_token):
    """Retrieve all devices from Automox using pagination"""
    headers = {
        "Authorization": "Bearer " + api_token,
        "Content-Type": "application/json"
    }

    query = {
        "limit": "500",
        "page": "0"
    }

    devices = []

    while True:
        response = http_get(AUTOMOX_API_URL, headers=headers, params=url_encode(query))

        if response.status_code != 200:
            print("Failed to fetch devices from Automox. Status:", response.status_code)
            return devices

        batch = json_decode(response.body)

        if not batch:
            break  # Stop fetching if no more results are returned

        devices.extend(batch)
        query["page"] = str(int(query["page"]) + 1)

    print("Loaded", len(devices), "devices")
    return devices

def build_assets(api_token):
    """Convert Automox device data into runZero asset format"""
    all_devices = get_automox_devices(api_token)
    assets = []

    for device in all_devices:
        custom_attrs = {
            "os_version": device.get("os_version", ""),
            "os_name": device.get("os_name", ""),
            "os_family": device.get("os_family", ""),
            "agent_version": device.get("agent_version", ""),
            "compliant": str(device.get("compliant", "")),
            "last_logged_in_user": device.get("last_logged_in_user", ""),
            "serial_number": device.get("serial_number", ""),
            "agent_status": device.get("status", {}).get("agent_status", "")
        }

        mac_address = ""
        if device.get("detail", {}).get("NICS"):
            mac_address = device["detail"]["NICS"][0].get("MAC", "")

        # Collect IPs
        ips = device.get("ip_addrs", []) + device.get("ip_addrs_private", [])

        assets.append(
            ImportAsset(
                id=str(device.get("id", new_uuid())),
                networkInterfaces=[build_network_interface(ips, mac_address)],
                hostnames=[device.get("name", "")],
                os_version=device.get("os_version", ""),
                os=device.get("os_name", ""),
                customAttributes=custom_attrs
            )
        )
    return assets

def build_network_interface(ips, mac=None):
    """Convert IPs and MAC addresses into a NetworkInterface object"""
    ip4s = []
    ip6s = []

    for ip in ips[:99]:
        if ip:
            ip_addr = ip_address(ip)
            if ip_addr.version == 4:
                ip4s.append(ip_addr)
            elif ip_addr.version == 6:
                ip6s.append(ip_addr)
        else:
            continue

    return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)

def main(**kwargs):
    """Main function to retrieve and return Automox asset data"""
    api_token = kwargs['access_secret']  # Use API token from runZero credentials

    assets = build_assets(api_token)
    
    if not assets:
        print("No assets retrieved from Automox")
        return None

    return assets