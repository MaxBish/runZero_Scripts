# ==============================================================================
# 1. LOAD LIBRARIES AND DEFINE CONSTANTS
# ==============================================================================
load('requests', 'Session')
load('json', json_decode='decode')
load('net', 'ip_address') 
load('runzero.types', 'ImportAsset', 'NetworkInterface') 
load('base64', base64_encode='encode') 
load('http', http_get='get') 

# Constants for the FireEye API
FIREEYE_BASE_URL = "XXXXXXXXXXXXXXX"
HOSTS_ENDPOINT "{}/hx/api/v3/hosts".format(FIREEYE_BASE_URL)
# Pagination size for each API request
PAGE_SIZE = 100

def fetch_hosts_data(session, current_offset):
    """
    Fetches one page of host data using the offset parameter.
    
    Returns: A list of host objects.
    """
    
    params = {
        "page_size": PAGE_SIZE,
        "offset": current_offset
    }
    
    print("Fetching page at offset {}...".format(current_offset))

    response = session.get(HOSTS_ENDPOINT, params=params, timeout=60)
    
    if not response or response.status_code != 200:
        print("Error: Failed to fetch hosts. Status code: {}".format(response.status_code))
        print("Response body: {}".format(response.body)) 
        return []

    print("Successfully fetched page at offset {}.".format(current_offset))
    response_data = json_decode(response.body)
    
    # Safely access nested dictionary fields for host list
    hosts_list = response_data.get('data', {}).get('entries', []) 
    
    if type(hosts_list) != "list":
        print("Error: Expected 'entries' field to be a list, received an unexpected data type ({}).".format(type(hosts_list)))
        return []

    return hosts_list

def build_network_interfaces(device):
    """
    Parses IP and MAC addresses from a single device record to create a 
    list of runZero NetworkInterface objects.
    """
    # Assuming primary_ip_address is a string
    ip_field = device.get('primary_ip_address')
    mac = device.get('primary_mac')
    
    ipv4s = []
    ipv6s = []

    # Process the single IP string from 'primary_ip_address' if it exists
    if ip_field:
        # Note: ip_address() must be imported via load('net', 'ip_address')
        addr = ip_address(ip_field) 
        if addr:
            if addr.version == 4:
                ipv4s.append(str(addr))
            else:
                ipv6s.append(str(addr))
    
    # Create and return a list containing a single NetworkInterface
    return [ NetworkInterface(macAddress=mac,
                              ipv4Addresses=ipv4s,
                              ipv6Addresses=ipv6s) ] 


def main(*args, **kwargs):
    """
    Main entrypoint for the runZero custom integration script.
    """
    
    # --- 1. Get Credentials (Username and Password) ---
    # Assuming Username:Password is in 'access_secret'
    user_pass_string = kwargs.get('access_secret')
    
    if not user_pass_string:
        print("Error: Username:Password not found in credentials.")
        return []

    # Split the string into username and password
    if ":" not in user_pass_string:
        print("Error: Credentials must be in the format 'username:password'.")
        return []
        
    username, password = user_pass_string.split(":", 1)

    # --- 3. Setup API Session and Headers ---
    session = Session()
    session.headers.set('Authorization', 'Basic ' + base64_encode("{}:{}".format(username, password)))
    session.headers.set('Accept', 'application/json')
    
    # --- 4. Paginate and Collect All Hosts ---
    import_assets = []
    current_offset = 0
    total_hosts_collected = 0
    hasNextPage = True
    
    # Loop indefinitely until we hit the 'break' condition (empty response)
    while hasNextPage:
        host_list = fetch_hosts_data(session, current_offset)
        
        if not host_list:
            if current_offset == 0:
                print("Initial fetch failed or returned no hosts.")
            else:
                print("End of results reached. Last offset attempted: {}.".format(current_offset))
            hasNextPage = False
        
        # Process hosts from the current page
        for host in host_list:
            host_id = host.get('_id')
            
            if not host_id:
                print("Skipping asset with no 'id'.")
                continue
                
            # --- Network Interface and IP/MAC processing ---
            network_interfaces = build_network_interfaces(host)

            # Put remaining fields into customAttributes (simplified structure)
            custom = {}
            for k, v in host.items():
                if k in ('_id','primary_ip_address','primary_mac','hostname','os'):
                    continue
                # Safely convert to string and truncate
                custom[k] = str(v)[:1023] 

            asset = ImportAsset(
                id=host_id,
                hostname=host.get('hostname', ''),
                os=host.get('os', {}).get('product_name', ''),
                network_interfaces=network_interfaces, 
                custom_attributes=custom
            )

            import_assets.append(asset)
            total_hosts_collected += 1
            
        # Increment the offset for the next loop iteration
        current_offset += PAGE_SIZE
            
    print("Successfully processed a total of {} hosts across all pages.".format(total_hosts_collected))
    return import_assets