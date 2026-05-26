load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_decode='decode')
load('net', 'ip_address')
load('http', http_get='get')
load('uuid', 'new_uuid')

AUTOMOX_BASE_URL = "https://console.automox.com/api"
AUTOMOX_SERVERS_URL = AUTOMOX_BASE_URL + "/servers"
AUTOMOX_ORGS_URL = AUTOMOX_BASE_URL + "/orgs"

def parse_int_or_none(value):
    if value == None:
        return None

    t = type(value)
    if t == "int":
        return value

    if t == "string":
        s = value.strip()
        if s == "":
            return None

        start = 0
        if s[0] == "+" or s[0] == "-":
            if len(s) == 1:
                return None
            start = 1

        for ch in s[start:]:
            if ch < "0" or ch > "9":
                return None

        return int(s)

    return None

def get_org_id(org_obj):
    # Account for schema variations seen across legacy/new API responses.
    for key in ["id", "organization_id", "org_id", "zone_id"]:
        if key in org_obj and org_obj.get(key) != None:
            return str(org_obj.get(key))
    return None

def normalize_list(decoded):
    if decoded == None:
        return []
    t = type(decoded)
    if t == "list":
        return decoded
    if t == "dict":
        if "data" in decoded and type(decoded["data"]) == "list":
            return decoded["data"]
        if "results" in decoded and type(decoded["results"]) == "list":
            return decoded["results"]
        if "items" in decoded and type(decoded["items"]) == "list":
            return decoded["items"]
        if "records" in decoded and type(decoded["records"]) == "list":
            return decoded["records"]
        fail("Unexpected dict response (no data/results/items/records list field).")
    fail("Unexpected response type: " + t)

def get_orgs(headers):
    orgs = []
    page = 0
    limit = 500

    while True:
        params = {"limit": str(limit), "page": str(page)}
        resp = http_get(AUTOMOX_ORGS_URL, headers=headers, params=params)

        if resp.status_code != 200:
            fail("Failed to fetch orgs from Automox: " + str(resp.status_code))

        batch = normalize_list(json_decode(resp.body))
        if not batch:
            break

        for o in batch:
            orgs.append(o)

        page = page + 1

    return orgs

def get_automox_devices(headers, org_id):
    devices = []
    page = 0
    limit = 500

    while True:
        params = {"limit": str(limit), "page": str(page), "include_details": "1", "o": str(org_id)}
        resp = http_get(AUTOMOX_SERVERS_URL, headers=headers, params=params)

        if resp.status_code != 200:
            print("Skipping org " + str(org_id) + " due to Automox /servers error: " + str(resp.status_code))
            break

        batch = normalize_list(json_decode(resp.body))
        if not batch:
            break

        for d in batch:
            devices.append(d)

        page = page + 1

    return devices

def build_network_interface(ips, mac=None):
    ip4s = []
    ip6s = []

    for ip in ips[:99]:
        if not ip:
            continue
        addr = ip_address(ip)
        if addr.version == 4:
            ip4s.append(addr)
        elif addr.version == 6:
            ip6s.append(addr)

    return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)

def build_network_interfaces_from_device(device):
    details = device.get("details", device.get("detail", {}))
    if type(details) == "dict":
        nics = details.get("NICS", None)
        if type(nics) == "list" and nics:
            out = []
            for nic in nics[:99]:
                mac = nic.get("MAC", "")
                ips = nic.get("IPS", [])
                out.append(build_network_interface(ips, mac))
            if out:
                return out

    ips = device.get("ip_addrs", []) + device.get("ip_addrs_private", [])
    return [build_network_interface(ips, "")]

def build_assets(api_token):
    headers = {"Authorization": "Bearer " + api_token, "Content-Type": "application/json"}

    # 1. Compile the list of target organizations with explicit positive device counts.
    target_orgs = []
    seen_org_ids = {}
    orgs = get_orgs(headers)
    
    for o in orgs:
        oid = get_org_id(o)
        if oid == None:
            continue

        if oid in seen_org_ids:
            continue

        device_count = parse_int_or_none(o.get("device_count", None))

        # Keep only orgs with explicit, positive device counts.
        if device_count == None or device_count <= 0:
            continue

        target_orgs.append(oid)
        seen_org_ids[oid] = True
            
    if not target_orgs:
        print("No organizations found with devices.")
        return []

    assets = []
    
    # 2. Iterate through each populated organization, fetching devices
    for org_id in target_orgs:
        devices = get_automox_devices(headers, org_id)

        for device in devices:
            device_id = device.get("id", new_uuid())

            custom_attrs = {
                "os_version": device.get("os_version", ""),
                "os_name": device.get("os_name", ""),
                "os_family": device.get("os_family", ""),
                "agent_version": device.get("agent_version", ""),
                "compliant": str(device.get("compliant", "")),
                "last_logged_in_user": device.get("last_logged_in_user", ""),
                "serial_number": device.get("serial_number", ""),
                "agent_status": device.get("status", {}).get("agent_status", ""),
            }

            assets.append(
                ImportAsset(
                    id=str(device_id),
                    networkInterfaces=build_network_interfaces_from_device(device),
                    hostnames=[device.get("name", "")],
                    os_version=device.get("os_version", ""),
                    os=device.get("os_family", "") + " " +  device.get("os_name", ""),
                    customAttributes=custom_attrs
                )
            )

    return assets

def main(**kwargs):
    api_token = kwargs.get("access_secret", None)

    if not api_token:
        fail("Missing access_secret (Automox API token).")

    assets = build_assets(api_token)
    if not assets:
        return None
    return assets