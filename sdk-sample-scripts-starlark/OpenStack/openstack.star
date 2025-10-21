load("runzero.types", "ImportAsset", "NetworkInterface")
load("json", json_encode="encode", json_decode="decode")
load("http", http_post="post", http_get="get")
load("net", "ip_address")
load("time", "parse_time")
load("uuid", "new_uuid")

# You must update these base URLs to match your OpenStack environment.
# Identity (keystone): 5000, Compute (nova): 8774, Application Container (zun/magnum): e.g., 9511
IDENTITY_API_BASE_URL = "https://<your-openstack-host>:5000"
COMPUTE_API_BASE_URL = "https://<your-openstack-host>:8774"

def get_auth_token(username, password, DOMAIN_NAME):
    """
    Authenticate with the OpenStack Identity API (Keystone) and get a token.
    """
    auth_url = "{}/v3/auth/tokens".format(IDENTITY_API_BASE_URL)
    headers = {"Content-Type": "application/json"}
    payload = {
        "auth": {
            "identity": {
                "methods": ["password"],
                "password": {
                    "user": {
                        "name": username,
                        "domain": {"name": DOMAIN_NAME},
                        "password": password
                    }
                }
            }
        }
    }

    print("Attempting to authenticate with OpenStack...")
    response = http_post(
        auth_url,
        headers=headers,
        body=bytes(json_encode(payload)),
        insecure_skip_verify=True,
        timeout=300
    )
    print("Authentication response status code: {}".format(response.status_code))

    if response.status_code != 201:  # 201 Created is the expected status code
        print("Authentication failed. Response body: {}".format(response.body))
        return None

    # The token is in the X-Subject-Token header
    print(response.body)
    token = response.headers.get("X-Subject-Token")
    if not token:
        print("Failed to get token from response headers.")
        return None

    print("Successfully authenticated and received token.")
    return token

---

def fetch_servers(auth_token):
    """
    Fetch all server details from the OpenStack Compute API (Nova) using the /detail endpoint.
    """
    servers_url = "{}/v2.1/servers/detail".format(COMPUTE_API_BASE_URL)
    headers = {
        "X-Auth-Token": auth_token,
        "Content-Type": "application/json"
    }

    print("Attempting to fetch servers from: {}".format(servers_url))
    response = http_get(servers_url, headers=headers, insecure_skip_verify=True, timeout=600)
    print("Servers response status code: {}".format(response.status_code))

    if response.status_code != 200:
        print("Failed to retrieve servers. Response body: {}".format(response.body))
        return None

    result = json_decode(response.body)
    servers = result.get("servers", [])
    print("Successfully retrieved {} servers.".format(len(servers)))
    return servers

def build_assets(servers):
    """
    Convert OpenStack servers into runZero ImportAsset objects.
    """
    assets = []
    print("Building assets from server data...")

    for server in servers:
        server_id = server.get("id", "")
        name = server.get("name", "")
        status = server.get("status", "")
        addresses = server.get("addresses", {}).get("private", [])

        network_interfaces = []
        for network_details in addresses:
            ipv4s = []
            ipv6s = []
            mac = []
            for ip_info in network_details:
                ip_address_str = ip_info.get("addr")
                if ip_address_str:
                    ip_obj = ip_address(ip_address_str)
                    if ip_obj and ip_obj.version == 4:
                        ipv4s.append(ip_obj)
                    elif ip_obj and ip_obj.version == 6:
                        ipv6s.append(ip_obj)

                mac_addr = ip_info.get("OS-EXT-IPS-MAC:mac_addr")
                if mac_addr:
                    mac.append(mac_addr)
            
            if ipv4s or ipv6s or mac:
                network_interfaces.append(NetworkInterface(
                    ipv4Addresses=ipv4s,
                    ipv6Addresses=ipv6s,
                    macAddress=mac
                ))

        # Build custom attributes
        custom_attrs = {
            "openstack_id": server_id,
            "openstack_status": status,
            "openstack_access_ipv4": server.get("access_ipv4", ""),
            "openstack_access_ipv6": server.get("access_ipv6", ""),
            "openstack_flavor_id": server.get("flavor", {}).get("id", ""),
            "openstack_project_id": server.get("tenant_id", "")
        }

        asset = ImportAsset(
            id=server_id,
            hostnames=[name],
            networkInterfaces=network_interfaces,
            os=server.get("os-extended-volumes:os_type", ""),
            osVersion=server.get("os-ext-srv-attr:distribution", ""),
            customAttributes=custom_attrs
        )
        assets.append(asset)

    print("Successfully built {} server assets.".format(len(assets)))
    return assets


def main(**kwargs):
    """
    Main entrypoint for the OpenStack custom integration.
    """
    # Retrieve credentials from the runZero task
    DOMAIN_NAME = kwargs.get("access_key")
    username = kwargs.get("access_secret").split(";")[0]
    password = kwargs.get("access_secret").split(";")[1]
    
    # Initialize a list to hold all assets (servers + containers)
    all_assets = []

    if not username or not password:
        print("Missing required parameters: access_key (username) or access_secret (password).")
        return None

    # Authenticate and get the token
    auth_token = get_auth_token(username, password, DOMAIN_NAME)
    if not auth_token:
        print("Authentication failed, cannot proceed.")
        return None
    
    # --- Server/Compute (Nova) Data ---
    print("--- Fetching Servers ---")
    servers = fetch_servers(auth_token)
    if servers:
        # Build and add server assets to the list
        server_assets = build_assets(servers)
        all_assets.extend(server_assets)
    else:
        print("No servers found or failed to retrieve servers.")

    # Return the combined list of all assets
    print("Total assets ready for import: {}.".format(len(all_assets)))
    return all_assets