## Snipe IT integration

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_get='get')

SNIPE_IT_URL = "https://inventory.<UPDATE ME>.com/api/v1/hardware"

def fetch_snipe_it_data(api_key):
    """Fetch asset data from Snipe-IT API."""
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": "Bearer " + api_key
    }

    response = http_get(SNIPE_IT_URL, headers=headers)
    if response.status_code != 200:
        print("Error fetching data:", response.status_code)
        return None

    return json_decode(response.body).get("rows", [])

def parse_network_interface(ip, mac):
    """Build a network interface for runZero."""
    ip4s, ip6s = [], []
    if ip:
        parsed_ip = ip_address(ip)
        if parsed_ip.version == 4:
            ip4s.append(parsed_ip)
        elif parsed_ip.version == 6:
            ip6s.append(parsed_ip)

    return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)

def build_assets(api_key):
    """Transform Snipe-IT data into runZero ImportAsset format."""
    devices = fetch_snipe_it_data(api_key)
    if not devices:
        print("No assets found in Snipe-IT")
        return []

    assets = []
    for asset in devices:
        asset_id = str(asset.get("id", ""))
        hostname = asset.get("name", "")

        # Handle nested fields safely
        model = asset.get("model") or {}
        manufacturer = asset.get("manufacturer") or {}
        category = asset.get("category") or {}
        location = asset.get("location") or {}
        custom_fields = asset.get("custom_fields") or {}

        custom_attrs = {
            "serial_number": asset.get("serial", ""),
            "os_model": model.get("name", ""),
            "manufacturer": manufacturer.get("name", ""),
            "device_type": category.get("name", ""),
            "os_version": (custom_fields.get("_snipeit_operating_system_16", {}) or {}).get("value", ""),
            "asset_tag": asset.get("asset_tag", ""),
            "location": location.get("name", "")
        }

        mac_address = (custom_fields.get("_snipeit_mac_address_1", {}) or {}).get("value", "")
        private_ip = (custom_fields.get("_snipeit_private_ip_15", {}) or {}).get("value", "")

        network_interface = parse_network_interface(private_ip, mac_address) if private_ip else None

        assets.append(
            ImportAsset(
                id=asset_id,
                hostnames=[hostname],
                networkInterfaces=[network_interface] if network_interface else [],
                customAttributes=custom_attrs
            )
        )

    return assets


def main(*args, **kwargs):
    """Entry point for the script."""
    api_key = kwargs["access_secret"]
    if not api_key:
        print("No API key provided!")
        return None

    assets = build_assets(api_key)
    if not assets:
        print("No assets retrieved")
        return None
    return assets
