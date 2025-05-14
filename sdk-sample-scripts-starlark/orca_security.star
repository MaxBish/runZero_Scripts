## ORCA

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_get='get', 'url_encode')
load('uuid', 'new_uuid')

ORCA_API_URL = "https://app.au.orcasecurity.io/api/assets"

def get_orca_assets(api_token):
    """Retrieve assets from Orca Security API"""
    headers = {
        "Authorization": "Bearer " + api_token,
        "Content-Type": "application/json"
    }

    query = {
        "limit": "100",  # Adjust limit as needed
        "page": "1"
    }

    assets = []
    while True:
        response = http_get(ORCA_API_URL, headers=headers, params=query)

        if response.status_code != 200:
            print("Failed to fetch assets from Orca Security. Status:", response.status_code)
            return assets

        batch = json_decode(response.body).get("assets", [])

        if not batch:
            break  # No more assets

        assets.extend(batch)
        query["page"] = str(int(query["page"]) + 1)

    print("Loaded", len(assets), "assets")
    return assets

def build_assets(api_token):
    """Convert Orca Security asset data into runZero asset format"""
    all_assets = get_orca_assets(api_token)
    assets = []

    for asset in all_assets:
        print(asset)
        custom_attrs = {
            "cloud_provider": asset.get("cloud_provider", ""),
            "account_id": asset.get("account_id", ""),
            "region": asset.get("region", ""),
            "service": asset.get("service", ""),
            "resource_type": asset.get("resource_type", ""),
            "status": asset.get("status", ""),
            "risk_level": asset.get("risk_level", ""),
            "last_seen": asset.get("last_seen", ""),
        }

        mac_address = asset.get("mac_address", "")

        # Collect IPs
        ips = asset.get("private_ips", [])

        assets.append(
            ImportAsset(
                id=str(asset.get("asset_unique_id", "")),
                networkInterfaces=[build_network_interface(ips, mac_address)],
                hostnames=[asset.get("name", "")],
                os_version=asset.get("os_version", ""),
                os=asset.get("os", ""),
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
    """Main function to retrieve and return Orca Security asset data"""
    api_token = kwargs['access_secret']  # Use API token from runZero credentials

    assets = build_assets(api_token)
    
    if not assets:
        print("No assets retrieved from Orca Security")
        return None

    return assets
