load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_get='get', 'url_encode')

# Constants
CISCO_ISE_HOST = "XXXXXXXXXXXXXX"
ENDPOINTS_API_URL = "{}/api/v1/endpoint".format(CISCO_ISE_HOST)
PAGE_SIZE = 50  # Number of endpoints per API call

def get_endpoints(username, password):
    """Retrieve all endpoints from Cisco ISE using pagination."""
    headers = {
        "Accept": "application/json",
        "Authorization": "Basic " + password,
        "Content-Type": "application/json",
    }

    endpoints = []
    page = 1
    hasNextPage = True

    while hasNextPage:
        url = "{}?page={}&size={}".format(ENDPOINTS_API_URL, page, PAGE_SIZE)
        response = http_get(url, headers=headers, timeout=600)

        if response.status_code == 401:
            print("Authentication failed: Invalid credentials.")
            return []
        elif response.status_code != 200:
            print("Failed to retrieve endpoints. Status: {}".format(response.status_code))
            return []

        batch = json_decode(response.body) or None
        print(batch)

        if len(batch) < 50:
            hasNextPage = False  # No more data to retrieve

        endpoints.extend(batch)
        page += 1

    return endpoints

def build_network_interface(ips, mac=None):
    """Build a runZero network interface object."""
    ip4s, ip6s = [], []

    for ip in ips[:99]:
        if ip:
            ip_addr = ip_address(ip)
            if ip_addr.version == 4:
                ip4s.append(ip_addr)
            elif ip_addr.version == 6:
                ip6s.append(ip_addr)

    return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)

def build_assets(endpoints):
    """Convert Cisco ISE endpoints into runZero assets."""
    assets = []

    for endpoint in endpoints:
        network = build_network_interface(ips=[endpoint.get("ipAddress", "")], mac=endpoint.get("mac", None))

        custom_attrs = {
            "vendor": endpoint.get("vendor", ""),
            "description": endpoint.get("description", ""),
            "deviceType": endpoint.get("deviceType", ""),
            "serialNumber": endpoint.get("serialNumber", ""),
            "softwareRevision": endpoint.get("softwareRevision", ""),
            "hardwareRevision": endpoint.get("hardwareRevision", ""),
            "productId": endpoint.get("productId", ""),
            "profileId": endpoint.get("profileId", ""),
        }

        assets.append(
            ImportAsset(
                id=endpoint.get("id", ""),
                hostnames=[endpoint.get("name", "")],
                networkInterfaces=[network],
                customAttributes=custom_attrs
            )
        )

    return assets

def main(*args, **kwargs):
    """Main function for Cisco ISE integration."""
    username = kwargs['access_key']
    password = kwargs['access_secret']

    if not username or not password:
        print("Missing authentication credentials.")
        return None

    endpoints = get_endpoints(username, password)

    if not endpoints:
        print("No endpoints found.")
        return None

    assets = build_assets(endpoints)

    if not assets:
        print("No assets created.")

    return assets