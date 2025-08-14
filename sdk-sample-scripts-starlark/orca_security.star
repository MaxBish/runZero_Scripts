load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_post='post')
load('uuid', 'new_uuid')

ORCA_API_BASE_URL = "https://app.au.orcasecurity.io"
# New Serving Layer API endpoint for queries
ORCA_SERVING_LAYER_QUERY_ENDPOINT = "/api/serving-layer/query"

def get_orca_assets(api_token):
    """Retrieve assets from Orca Security Serving Layer API using POST /query endpoint."""
    headers = {
        "Authorization": "Bearer " + api_token,
        "Content-Type": "application/json"
    }

    all_assets = []
    start_at_index = 0
    limit = 100 # Can be increased up to 10000 per request
    hasNextPage = True

    while hasNextPage:
        # Construct the JSON request body for the Serving Layer API
        request_body = {
            "query": {
                "models": ["Inventory"],
                "type": "object_set"
            },
            "limit": limit,
            "start_at_index": start_at_index,
            # -- NEW: Corrected field name from order_by[] to order_by --
            "order_by": ["-state.orca_score"],
            "select": [
                "Name", # Asset name/hostname
                "AssetUniqueId", # Unique ID for the asset
                "CloudAccount.Name", # Cloud account name
                "CloudAccount.CloudProvider", # Cloud provider (e.g., AWS, Azure)
                # -- NEW: Corrected field name to state.orca_score --
                "state.orca_score", # Orca risk score
                "RiskLevel", # Risk level (e.g., Critical, High, Medium, Low, Informational)
                "LastSeen", # Timestamp of last observation
                "PrivateIps", # List of private IP addresses
                "PublicIps", # List of public IP addresses
                "DistributionName", # Potential OS name
                "DistributionVersion", # Potential OS version
                "Type", # General asset type
                "NewCategory", # New category for the asset
                "NewSubCategory", # New sub-category for the asset
                "Status", # Asset status
                "Tags", # Associated tags
                "IsInternetFacing", # Boolean indicating internet exposure
                "ConsoleUrlLink" # Link to the asset in Orca console
                # Note: MAC addresses are not explicitly listed in common 'Inventory' select examples.
                # If crucial, further investigation with Orca support might be needed for their API.
            ],
            "full_graph_fetch": {
                "enabled": True
            },
            "use_cache": True,
            "max_tier": 2
        }
        
        # Execute the POST request with the JSON body
        response = http_post(ORCA_API_BASE_URL + ORCA_SERVING_LAYER_QUERY_ENDPOINT, headers=headers, body=bytes(json_encode(request_body)),timeout=600)

        if response.status_code != 200:
            print("Failed to fetch assets from Orca Security. Status: {}".format(response.status_code))
            print("Response body: {}".format(response.body)) # Print response body for debugging
            return all_assets

        response_json = json_decode(response.body)
        # Assets are now expected under the "results" key
        batch = response_json.get("results", [])

        if not batch:
            hasNextPage = False
            break # No more assets to retrieve

        all_assets.extend(batch)
        start_at_index += limit # Increment index for next page of results

    print("Loaded {} assets from Orca Serving Layer API".format(len(all_assets)))
    return all_assets

def build_assets(api_token):
    """Convert Orca Security asset data into runZero ImportAsset format."""
    all_orca_assets = get_orca_assets(api_token)
    assets_for_runzero = []

    for asset in all_orca_assets:
        # Extract fields, handling potential missing data with default values
        asset_id = asset.get("AssetUniqueId", "") # Use Orca's unique ID as runZero ID
        hostname = asset.get("Name", "")
        os_name = asset.get("DistributionName", "") # Mapped to OS name
        os_version = asset.get("DistributionVersion", "") # Mapped to OS version
        risk_level = str(asset.get("RiskLevel", ""))
        last_seen = asset.get("LastSeen", "")
        
        # CloudAccount details are nested
        cloud_account = asset.get("CloudAccount", {})
        cloud_provider = cloud_account.get("CloudProvider", "")
        account_name = cloud_account.get("Name", "")
        
        # Collect all IP addresses (private and public)
        private_ips_raw = asset.get("PrivateIps", [])
        public_ips_raw = asset.get("PublicIps", [])
        
        all_ips = []
        # Check type for private_ips_raw. Lists are iterable.
        if type(private_ips_raw) == type([]):
            all_ips.extend(private_ips_raw)
        # Check type for public_ips_raw. Lists are iterable.
        if type(public_ips_raw) == type([]):
            all_ips.extend(public_ips_raw)

        # MAC Address is not directly available in the provided 'select' options for 'Inventory'.
        # It will be an empty string unless Orca exposes it differently or it's a linked entity.
        mac_address = ""

        # Build custom attributes for runZero
        custom_attrs = {
            "orca_cloud_provider": cloud_provider,
            "orca_account_name": account_name,
            "orca_service": asset.get("Type", ""), # Using 'Type' as a general service/resource identifier
            "orca_resource_type": asset.get("NewCategory", "") if asset.get("NewCategory") != "" else asset.get("Type", ""), # Prefer NewCategory, fallback to Type
            "orca_status": asset.get("Status", ""),
            "orca_risk_level": risk_level,
            "orca_last_seen": last_seen,
            "orca_tags": json_encode(asset.get("Tags", [])), # Tags are a list, encode to JSON string
            "orca_is_internet_facing": str(asset.get("IsInternetFacing", False)), # Convert boolean to string
            "orca_console_url_link": asset.get("ConsoleUrlLink", ""),
            # -- NEW: Correctly parse orca_score from nested 'state' field --
            "orca_score": str(asset.get("state", {}).get("orca_score", ""))
        }

        # Filter out any non-string or empty IP entries before processing
        valid_ips_for_interface = []
        for ip_val in all_ips:
            if type(ip_val) == type("") and len(ip_val) > 0: # Check if it's a non-empty string
                valid_ips_for_interface.append(ip_val)

        # Build network interface. If no valid IPs or MAC, it will return None.
        network_interface = build_network_interface(valid_ips_for_interface, mac_address)

        # Only add asset if it has a valid network interface (IPs or MAC)
        if network_interface != None: # Explicit check for None
            assets_for_runzero.append(
                ImportAsset(
                    id=asset_id,
                    networkInterfaces=[network_interface],
                    hostnames=[hostname] if hostname != "" else [], # Hostnames should be a list, add only if not empty string
                    os_version=os_version,
                    os=os_name,
                    customAttributes=custom_attrs
                )
            )
    return assets_for_runzero

def build_network_interface(ips, mac=None):
    """Convert a list of IPs and an optional MAC address into a runZero NetworkInterface object."""
    ipv4_addresses = []
    ipv6_addresses = []

    for ip_str_candidate in ips:
        # -- NEW: Add an additional check for valid string format --
        if type(ip_str_candidate) == type("") and len(ip_str_candidate) > 0 and ('.' in ip_str_candidate or ':' in ip_str_candidate):
            ip_addr = ip_address(ip_str_candidate)
            if ip_addr.version == 4:
                ipv4_addresses.append(ip_addr)
            elif ip_addr.version == 6:
                ipv6_addresses.append(ip_addr)

    # Only return a NetworkInterface if there's at least one IP or a MAC address
    if ipv4_addresses or ipv6_addresses or mac:
        return NetworkInterface(macAddress=mac, ipv4Addresses=ipv4_addresses, ipv6Addresses=ipv6_addresses)
    return None # Return None if no useful network information can be extracted

def main(**kwargs):
    """Main function to retrieve and return Orca Security asset data for runZero."""
    # Retrieve the API token from runZero credentials, expected as 'access_secret'
    api_token = kwargs.get('access_secret')
    if not api_token:
        print("Error: ORCA API token (access_secret) not provided in credentials.")
        return None

    assets = build_assets(api_token)
    
    if assets == None or len(assets) == 0: # Explicit check for None or empty list
        print("No assets retrieved from Orca Security or no valid assets with network interfaces found.")
        return None

    print("Successfully processed {} assets for runZero import.".format(len(assets)))
    return assets