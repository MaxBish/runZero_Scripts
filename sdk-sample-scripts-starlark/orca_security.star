"""Module for importing assets from Orca Security API into runZero."""

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_decode='decode')
load('http', http_get='get', 'url_encode')
load('net', 'ip_address')
load('flatten_json', 'flatten')

# --- Configuration ---
BASE_URL = "https://api.orcasecurity.io"

def build_network_interfaces(data_node):
    """Extracts and validates IPv4, IPv6 addresses and MAC address from Orca asset data.
    
    Args:
      data_node: A dictionary containing asset data with potential IP and MAC address information.
    
    Returns:
      A list of NetworkInterface objects, or an empty list if no valid network data is found.
    """
    ip4s = []
    ip6s = []
    
    # Safely handle both PascalCase and snake_case depending on how Orca formats the payload
    public_ips = data_node.get('PublicIps') or data_node.get('public_ips') or []
    private_ips = data_node.get('PrivateIps') or data_node.get('private_ips') or []
    macs = data_node.get('MacAddresses') or data_node.get('mac_addresses') or []
    
    all_ips = []
    for ip in public_ips:
        if ip and ip not in all_ips:
            all_ips.append(ip)
            
    for ip in private_ips:
        if ip and ip not in all_ips:
            all_ips.append(ip)

    # Validate IP addresses
    for ip in all_ips:
        addr = ip_address(ip) 
        if addr.version == 4:
            ip4s.append(addr)
        elif addr.version == 6:
            ip6s.append(addr)
            
    # Safely grab the first MAC address if one exists
    mac_val = macs[0] if type(macs) == "list" and len(macs) > 0 else None
            
    # If there is no network data at all, return an empty list
    if not ip4s and not ip6s and not mac_val:
        return []
        
    return [NetworkInterface(macAddress=mac_val, ipv4Addresses=ip4s, ipv6Addresses=ip6s)]


def main(**kwargs):
    """Retrieves assets from Orca Security API and maps them to runZero ImportAssets.
    
    Args:
      **kwargs: Keyword arguments containing 'access_secret' with the Orca API token.
    
    Returns:
      A list of ImportAsset objects mapped from Orca Security API response.
    """
    
    # 1. Retrieve the Orca API Token from runZero credentials
    api_token = kwargs.get('access_secret')
    if not api_token:
        print("Error: Missing Orca API Token in 'access_secret' field.")
        return []

    # 2. Set up headers for Orca API authentication
    headers = {
        "Authorization": "Token {}".format(api_token),
        "Accept": "application/json"
    }
    
    assets = []
    next_page_token = None

    params = {
        "limit": "100",
        "query": "vm"
    }
    
    # 3. Handle Pagination (Starlark requires bounded for-loops instead of while loops)
    for page in range(1000): # Safely loop up to 100,000 assets

        if next_page_token:
            params["next_page_token"] = next_page_token

        encoded_params = url_encode(params)
        
        # Construct the paginated URL
        url = "{}/api/sonar/query?{}".format(BASE_URL, encoded_params)

        # Make the API request
        response = http_get(url, headers=headers, timeout=300)

        if response.status_code != 200:
            print("Orca API Error: Received status code {} - {}".format(response.status_code, response.body))
            break
        
        data = json_decode(response.body)
        
        # Extract the list of assets from the response
        orca_items = data.get('data', [])
        
        # 4. Map Orca objects to runZero ImportAssets
        for item in orca_items:
            
            print(item)
            asset_id = item.get('asset_unique_id')
            if not asset_id:
                continue
                
            # Depending on the payload format, network/OS info is usually in 'data' or 'compute'
            data_node = item.get('data')
            
            # Hostname fallback logic
            hostname = data_node.get('Name')
            hostnames = [hostname] if hostname else []

            # Build network interfaces
            net_ifs = build_network_interfaces(data_node)
            
            # Use flatten to automatically map ALL deep metadata to custom attributes
            flat_data = flatten(data_node)
            custom_attrs = {}
            for key, value in flat_data.items():
                if value != None:
                    custom_attrs["{}".format(key)] = str(value)

            # Add high-level identifiers
            if item.get('cloud_provider'):
                custom_attrs["cloud_provider"] = str(item.get('cloud_provider'))
            if item.get('cloud_account_id'):
                custom_attrs["cloud_account_id"] = str(item.get('cloud_account_id'))

            # Create and append the ImportAsset
            assets.append(ImportAsset(
                id=asset_id,
                hostnames=hostnames,
                os=data_node.get('DistributionName') or data_node.get('os_distribution') or item.get('asset_distribution_name'),
                osVersion=data_node.get('DistributionVersion') or data_node.get('os_version') or item.get('asset_distribution_version'),
                networkInterfaces=net_ifs,
                customAttributes=custom_attrs
            ))
            
        # Check if there are more pages
        hasNextPage = data.get('has_next_page', False)
        next_page_token = data.get('next_page_token')
        
        # Break the bounded for-loop if we've reached the end
        if not hasNextPage or not next_page_token:
            break

    print("Successfully mapped {} assets from Orca.".format(len(assets)))
    return assets