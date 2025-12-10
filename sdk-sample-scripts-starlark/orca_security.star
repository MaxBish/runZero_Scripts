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
        "Authorization": "TOKEN " + api_token,
        "Content-Type": "application/json"
    }

    all_assets = []
    start_at_index = 0
    limit = 10000
    hasNextPage = True
    
    while hasNextPage:
        ## New request body
        request_body = {
            "query": {
                "models": ["Inventory"],
                "type": "object_set"
            },
            "limit": limit,
            "start_at_index": start_at_index,
            "order_by[]": ["-OrcaScore"],
            "select": [
                "Name",
                "CiSource",
                "CloudAccount.Name",
                "CloudAccount.CloudProvider",
                "state.orca_score",
                "RiskLevel",
                "group_unique_id",
                "UiUniqueField",
                "IsInternetFacing",
                "Tags",
                "NewCategory",
                "NewSubCategory",
                "AssetUniqueId",
                "ConsoleUrlLink",
                "PrivateIps",
                "PublicIps",
                "DistributionName",
                "DistributionVersion",
                "Type",
                "Status"
            ],
            "get_results_and_count": False,
            "full_graph_fetch": {
                "enabled": True
            },
            "use_cache": True,
            "max_tier": 2,
            "ui": True
        }
        
        print("Fetching page starting at index: {}".format(start_at_index))
        response = http_post(
            ORCA_API_BASE_URL + ORCA_SERVING_LAYER_QUERY_ENDPOINT,
            headers=headers,
            body=bytes(json_encode(request_body)),
            timeout=600,
            insecure_skip_verify=True
        )

        if response.status_code != 200:
            print("Failed to fetch assets from Orca Security. Status: {}".format(response.status_code))
            print("Response body: {}".format(response.body))
            return all_assets

        response_json = json_decode(response.body)
        batch = response_json.get("data", [])

        if not batch:
            print("No more assets found.")
            break
        
        all_assets.extend(batch)
        start_at_index += len(batch)
        
        if len(batch) < limit:
            print("Reached the last page. Total assets: {}".format(len(all_assets)))
            hasNextPage = False
            break

    return all_assets

def build_assets(api_token):
    """Convert Orca Security asset data into runZero ImportAsset format."""
    all_orca_assets = get_orca_assets(api_token)
    assets_for_runzero = []

    for asset in all_orca_assets:
        print(asset)
        asset_id = asset.get("AssetUniqueId", "") 
        hostname = asset.get("Name", "")
        os_name = asset.get("DistributionName", "")
        os_version = asset.get("DistributionVersion", "")
        risk_level = str(asset.get("RiskLevel", ""))
        last_seen = asset.get("LastSeen", "")
        
        cloud_account = asset.get("CloudAccount", {})
        cloud_provider = cloud_account.get("CloudProvider", "")
        account_name = cloud_account.get("Name", "")
        
        private_ips_raw = asset.get("PrivateIps", [])
        public_ips_raw = asset.get("PublicIps", [])
        
        all_ips = []
        if type(private_ips_raw) == type([]):
            all_ips.extend(private_ips_raw)
        if type(public_ips_raw) == type([]):
            all_ips.extend(public_ips_raw)

        mac_address = ""

        custom_attrs = {
            "orca_cloud_provider": cloud_provider,
            "orca_account_name": account_name,
            "orca_service": asset.get("Type", ""),
            "orca_resource_type": asset.get("NewCategory", "") if asset.get("NewCategory") != "" else asset.get("Type", ""),
            "orca_status": asset.get("Status", ""),
            "orca_risk_level": risk_level,
            "orca_last_seen": last_seen,
            "orca_tags": json_encode(asset.get("Tags", [])),
            "orca_is_internet_facing": str(asset.get("IsInternetFacing", False)),
            "orca_score": str(asset.get("OrcaScore", ""))
        }

        valid_ips_for_interface = []
        for ip_val in all_ips:
            if type(ip_val) == type("") and len(ip_val) > 0:
                ip_obj = ip_address(ip_val)
                if ip_obj:
                    valid_ips_for_interface.append(ip_val)

        network_interface = build_network_interface(valid_ips_for_interface, mac_address)

        if network_interface != None:
            assets_for_runzero.append(
                ImportAsset(
                    id=asset_id,
                    networkInterfaces=[network_interface],
                    hostnames=[hostname] if hostname != "" else [],
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
        if type(ip_str_candidate) == type("") and len(ip_str_candidate) > 0 and ('.' in ip_str_candidate or ':' in ip_str_candidate):
            ip_obj = ip_address(ip_str_candidate)
            if ip_obj and ip_obj.version == 4:
                ipv4_addresses.append(ip_obj)
            elif ip_obj and ip_obj.version == 6:
                ipv6_addresses.append(ip_obj)

    if ipv4_addresses or ipv6_addresses:
        return NetworkInterface(macAddress=mac, ipv4Addresses=ipv4_addresses, ipv6Addresses=ipv6_addresses)
    return None

def main(**kwargs):
    """Main function to retrieve and return Orca Security asset data for runZero."""
    api_token = kwargs.get('access_secret')
    if not api_token:
        print("Error: ORCA API token (access_secret) not provided in credentials.")
        return None

    assets = build_assets(api_token)
    
    if assets == None or len(assets) == 0:
        print("No assets retrieved from Orca Security found.")
        return None

    print("Successfully processed {} assets for runZero import.".format(len(assets)))
    return assets