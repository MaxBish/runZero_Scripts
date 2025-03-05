load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_get='get', 'url_encode')

CISCO_ISE_HOST = "<UPDATE_ME>"  # Example: https://ise.example.com
ENDPOINTS_API_URL = "{}/api/v1/endpoint"
PAGE_SIZE = 100  # Number of endpoints per API call

def get_endpoints(username, password):
    """Retrieve all endpoints from Cisco ISE using pagination"""
    headers = {
        "Accept": "application/json",
        "Authorization": "Basic "+password,
        "Content-Type": "application/json",
    }

    endpoints = []
    page = 1

    while True:
        url = ENDPOINTS_API_URL.format(CISCO_ISE_HOST) + "?size={}&page={}".format(PAGE_SIZE, page)
        response = http_get(url, headers=headers)

        if response.status_code == 401:
            print("Authentication failed: Invalid credentials.")
            return []
        elif response.status_code != 200:
            print("Failed to retrieve endpoints. Status: {}".format(response.status_code))
            break

        response_json = json_decode(response.body)
        batch = response_json

        if not batch:
            break  # No more data to retrieve

        endpoints.extend(batch)
        page += 1

    return endpoints

def build_assets(endpoints):
    """Convert Cisco ISE endpoints into runZero assets"""
    assets = []
    
    for endpoint in endpoints:
        endpoint_id = endpoint.get("id", "")
        hostname = endpoint.get("name", "")
        ip = endpoint.get("ipAddress", "")
        mac = endpoint.get("mac", "")
        vendor = endpoint.get("vendor", "")
        description = endpoint.get("description", "")
        device_type = endpoint.get("deviceType", "")
        serial_number = endpoint.get("serialNumber", "")
        software_revision = endpoint.get("softwareRevision", "")
        hardware_revision = endpoint.get("hardwareRevision", "")
        product_id = endpoint.get("productId", "")
        profile_id = endpoint.get("profileId", "")

        # Build network interfaces
        network = build_network_interface(ips=[ip], mac=mac if mac else None)

        # Manually build customAttributes for compatibility
        custom_attrs = {
            "vendor": vendor,
            "description": description,
            "deviceType": device_type,
            "serialNumber": serial_number,
            "softwareRevision": software_revision,
            "hardwareRevision": hardware_revision,
            "productId": product_id,
            "profileId": profile_id,
        }

        assets.append(
            ImportAsset(
                id=endpoint_id,
                hostnames=[hostname],
                networkInterfaces=[network],
                customAttributes=custom_attrs
            )
        )

    return assets

def build_network_interface(ips, mac):
    """Build runZero network interfaces"""
    ip4s = []
    ip6s = []

    for ip in ips[:99]:
        if ip:
            ip_addr = ip_address(ip)
            if ip_addr.version == 4:
                ip4s.append(ip_addr)
            elif ip_addr.version == 6:
                ip6s.append(ip_addr)

    return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)

def main(*args, **kwargs):
    """Main function for Cisco ISE integration"""
    username = kwargs['access_key']  # Username stored in runZero credentials
    password = kwargs['access_secret']  # Password stored in runZero credentials

    endpoints = get_endpoints(username, password)
    
    if not endpoints:
        print("No endpoints found.")
        return None

    assets = build_assets(endpoints)
    
    if not assets:
        print("No assets created.")
    
    return assets