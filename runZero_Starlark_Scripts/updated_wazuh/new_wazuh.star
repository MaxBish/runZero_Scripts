# This is a runZero Custom Integration, please see https://github.com/runZeroInc/runzero-custom-integrations for details.
# This script was generated with AI.

CONFIG = {
    "id": "runzero-wazuh",
    "name": "Wazuh",
    "type": "inbound",
    "description": "Imports agents from a Wazuh manager.",
    "version": "1",
    "maturity": "beta",
    "minVersion": "5.1.260818.0",
    # This integration reports ONE population - Wazuh agents - but two grades of
    # identifier, so the policy is declared per asset type here and the script
    # picks a type per agent from whether the record carries a registration
    # timestamp. See build_asset_id and registration_key for the id halves.
    #
    # no-type-break, because the split is about identifier quality inside one
    # population and not about two different kinds of thing. An agent that
    # reports no dateAdd today can report one tomorrow - a Wazuh upgrade, a
    # re-enrollment, an API that starts populating the field - and it is the same
    # agent on the same host throughout, so nothing about a type change should be
    # allowed to veto a merge on its own.
    #
    # Be aware of what that does NOT buy, because it is easy to over-read:
    # gaining dateAdd also changes the foreign id, from wazuh:<ns>:agent:<n> to
    # wazuh:<ns>:agent:<n>:<reg>. Two foreign ids from one custom integration
    # cannot sit on one asset whatever the break flags say, so that particular
    # transition still forks and is reconciled in runZero. no-type-break is
    # necessary but not sufficient here; it is declared so the type boundary is
    # not a SECOND, independent reason for the same fork.
    "matchBehavior": "no-type-break",
    "assetTypeBehavior": {
        # Registration time pins the ordinal, so the id can no longer be
        # inherited by a later agent and is safe to merge on. An agent's own
        # addressing must not then veto that merge: a laptop that moves
        # between networks, a VM that is renamed, or a host that gains an
        # interface is the same agent under the same id.
        "agent": "no-mac-break no-ip-break no-name-break",
        # Deliberately absent: "agent-unpinned", the type used when the record
        # carries no dateAdd. Its id CAN be inherited by a later agent reusing
        # the ordinal -- Wazuh allocates ids from a counter seeded off the
        # highest id in client.keys, and <auth><purge> defaults to yes -- and a
        # disagreeing MAC is then the only thing that can stop an unrelated new
        # host being merged onto the old agent's asset. Wazuh's syscollector
        # data is read off the host itself, so it is good enough evidence to
        # break on. With no entry here that type keeps the platform default,
        # every flag on, which is exactly what it needs.
    },
    "params": [
        {
            "key": "url",
            "label": "Wazuh API URL",
            "type": "url",
            "required": False,
            "placeholder": "https://wazuh-manager:55000",
            "description": "Full base URL of the Wazuh manager API. Set this for a deployment that is not plain https on the API port -- behind a reverse proxy, on a path prefix, or on http. When empty, the URL is composed from the hostname and port below.",
        },
        {
            "key": "hostname",
            "label": "Wazuh manager hostname or IP",
            "type": "string",
            "required": False,
            "placeholder": "wazuh-manager or 10.1.2.3",
            "description": "Used to compose https://<hostname>:<port> when the URL above is empty.",
        },
        {
            "key": "port",
            "label": "Wazuh API port",
            "type": "int",
            "required": False,
            "default": 55000,
        },
        {
            "key": "username",
            "label": "Username",
            "type": "string",
            "required": True,
        },
        {
            "key": "password",
            "label": "Password",
            "type": "secret",
            "required": True,
        },
        {
            "key": "max_pages",
            "label": "Maximum pages to retrieve",
            "type": "int",
            "required": False,
            "default": 20000,
            "min": 1,
            "description": "Safety ceiling on the paging walk. Raise it if a run reports hitting the limit.",
        },
        {
            "key": "requests_per_minute",
            "label": "Syscollector requests per minute",
            "type": "int",
            "required": False,
            "default": 240,
            "min": 0,
            "description": "Budget for agent listing and syscollector requests, including additional pages and retries. Keep below the Wazuh API max_request_per_minute (default 300). 0 disables the throttle.",
        },
    ],
    "includes": {
        "tls_": OPTIONS_TLS,
        "http_": OPTIONS_HTTP,
    },
}

load('runzero.types', 'ImportAsset', 'NetworkInterface', 'to_custom_attributes')
load('json', json_decode='decode')
load('net', 'ip_address', 'routable_ip', 'clean_hostnames', 'mac_key')
load('http', http_post='post', http_get='get', 'url_parse')
load('base64', base64_encode='encode')
load('time', 'sleep')
load('re', re_sub='sub')
load('kwargs', 'require', 'get_string', 'get_int', 'get_http_options')

# Wazuh caps `limit` at 500 on the /agents endpoint and answers a larger value
# with error 1405, so this is the vendor's maximum page, not a choice.
PAGE_SIZE = 500

# The repo-wide record target for a bounded walk: no integration should import
# more than ten million records in one run, so the page ceiling is that target
# divided by the page size. At 500 agents a page that is 20,000 pages. The page
# size is fixed by the vendor; the page COUNT is not, which is why the ceiling
# is exposed as max_pages and the message that reports hitting it says so.
#
# The ceiling is a backstop, not the working guard. The walk's only exit is a
# page with no affected_items, so a manager that ignores `offset` -- or a proxy
# replaying a cached response -- never reaches it and re-reads the same 500
# agents forever. The no-progress check catches that on the first repeat. Either
# stop fails the task so a truncated import cannot appear complete.
MAX_RECORDS = 10000000
MAX_PAGES = (MAX_RECORDS + PAGE_SIZE - 1) // PAGE_SIZE

def device_type_for_os(os_data):
    """Only an explicit server OS edition supplies a device-type hint."""
    if type(os_data) != 'dict':
        return ""
    name = str(os_data.get('name', '') or '').lower()
    if 'server' in re_sub(r"[^a-z0-9]+", " ", name).split():
        return "Server"
    return ""

def page_signature(agents):
    """A fingerprint of one page's rows, used to notice a manager that answers
    every offset with the same page."""
    ids = []
    for a in agents:
        if type(a) == 'dict':
            ids.append(str(a.get('id', '')))
        else:
            ids.append('')
    return ','.join(ids)

def reported_total(data):
    """Wazuh returns total_affected_items alongside affected_items. Read it when
    it is there and answer None when it is not -- a total this script invented
    would be worse than saying the API did not report one."""
    if type(data) != 'dict':
        return None
    total = data.get('total_affected_items')
    if type(total) == 'int' and total >= 0:
        return total
    return None

def retrieved_of(reported, total):
    """The 'retrieved x' clause of a truncation message, in the with-total form
    when the API reported one and the no-total form when it did not."""
    if total == None:
        return 'retrieved {} assets, total not reported'.format(reported)
    return 'retrieved {}/{} available assets'.format(reported, total)

# --- Wazuh API helpers ---
def authenticate_wazuh(host, username, password, config):
    """
    Authenticate with Wazuh API and retrieve JWT token.

    Args:
        host: Wazuh host URL (e.g., https://wazuh-manager:55000)
        username: Wazuh username
        password: Wazuh password

    Returns:
        JWT token string; authentication failures abort the task.
    """
    auth_url = "{}/security/user/authenticate".format(host)

    # Create basic auth header
    credentials = "{}:{}".format(username, password)
    auth_header = "Basic {}".format(base64_encode(credentials))

    headers = {
        'Authorization': auth_header,
        'Content-Type': 'application/json'
    }

    response = http_post(auth_url, timeout=600, **get_http_options(config, headers=headers))

    if response.status_code != 200:
        fail("Wazuh authentication failed with status {}. Check the username, password, and that the account is permitted from this source address.".format(
            response.status_code))

    auth_data = json_decode(response.body)

    if auth_data.get('error', 1) != 0:
        fail("Wazuh rejected the authentication request: {}".format(
            auth_data.get('message', 'unspecified error')))

    token = auth_data.get('data', {}).get('token', "")
    if not token:
        fail("Wazuh accepted the credentials but returned no token")

    print("Successfully authenticated with Wazuh API")
    return token

def wazuh_get(host, ctx, path, params):
    """Pace every data request and retry once with a fresh JWT on expiry."""
    for attempt in range(2):
        if ctx['throttle_ms'] > 0:
            sleep("{}ms".format(ctx['throttle_ms']))
        response = http_get(
            host + path,
            params=params,
            timeout=600,
            **get_http_options(ctx['config'], headers={
                'Authorization': 'Bearer {}'.format(ctx['token']),
                'Content-Type': 'application/json',
            })
        )
        if response.status_code != 401 or attempt == 1:
            return response
        print("Token expired, re-authenticating...")
        config = ctx['config']
        ctx['token'] = authenticate_wazuh(host, config['username'], config['password'], config)

def get_wazuh_agents(host, ctx, max_pages, handle_agents):
    """
    Retrieve agents from Wazuh using pagination, streaming each page to the
    handler as it arrives so the full agent list is never buffered.

    Args:
        host: Wazuh host URL
        ctx: shared run state carrying the JWT (which mid-run re-auth may
             replace) and the CONFIG kwargs
        max_pages: page ceiling
        handle_agents: called with each page's agent list; whatever it does
             (enrich, build, report) happens before the next page is fetched

    Returns:
        Count of agents fetched across every page.
    """
    fetched = 0
    offset = 0
    pages = 0
    total = None
    capped = True
    last_signature = None
    walk_error = None

    for _page in range(0, max_pages):

        params = {
            'offset': offset,
            'limit': PAGE_SIZE
        }
        response = wazuh_get(host, ctx, "/agents", params)

        if response.status_code != 200:
            walk_error = "could not fetch agents: status {}".format(response.status_code)
            capped = False
            break

        response_data = json_decode(response.body)

        if type(response_data) != 'dict' or response_data.get('error', 1) != 0:
            walk_error = "agent listing API error: {}".format(response_data.get('message', 'Unknown error') if type(response_data) == 'dict' else 'invalid response')
            capped = False
            break
        data = response_data.get('data', {})
        if type(data) != 'dict' or type(data.get('affected_items')) != 'list':
            walk_error = "invalid agent inventory response"
            capped = False
            break
        if total == None:
            total = reported_total(data)
        agents_batch = data.get('affected_items', [])

        if not agents_batch:
            if total != None and fetched < total:
                walk_error = "agent listing ended early ({})".format(retrieved_of(fetched, total))
            capped = False  # No more agents to fetch
            break

        pages += 1

        # A page whose agent ids are identical to the previous page's means the
        # manager ignored `offset` or replayed a cached response. The walk's
        # only exit is an empty page, so a repeat produces no exit at all and
        # the same 500 agents would be re-read to the ceiling. Stop on the
        # first repeat, and stop BEFORE handling, so the replayed page is not
        # imported twice.
        signature = page_signature(agents_batch)
        if signature == last_signature:
            walk_error = 'paging stopped after {} pages (API returned the same page twice, {})'.format(
                pages, retrieved_of(fetched, total))
            capped = False
            break
        last_signature = signature

        fetched += len(agents_batch)
        handle_agents(agents_batch)

        offset += PAGE_SIZE

    if capped:
        walk_error = 'page limit of {} hit (integration safety limit, {}) - raise the max_pages parameter to import the rest'.format(
            max_pages, retrieved_of(fetched, total))

    print("Retrieved {} agents from Wazuh".format(fetched))
    if walk_error:
        fail("wazuh: " + walk_error)
    return fetched

def get_agent_network_data(host, ctx, agent_id, endpoint, max_pages):
    """Read a complete syscollector inventory, or warn and discard it."""
    rows = []
    offset = 0
    last_batch = None
    error = "page limit of {} hit; raise max_pages".format(max_pages)
    for _page in range(max_pages):
        response = wazuh_get(host, ctx, "/syscollector/{}/{}".format(agent_id, endpoint), {
            'offset': offset,
            'limit': PAGE_SIZE,
        })
        if response.status_code != 200:
            error = "status {}".format(response.status_code)
            break
        body = json_decode(response.body)
        if type(body) != 'dict' or body.get('error', 1) != 0:
            error = "API error: {}".format(body.get('message', 'unknown error') if type(body) == 'dict' else 'invalid response')
            break
        data = body.get('data')
        if type(data) != 'dict' or type(data.get('affected_items')) != 'list':
            error = "invalid inventory response"
            break
        batch = data['affected_items']
        total = reported_total(data)
        if not batch:
            if total != None and len(rows) < total:
                error = "inventory ended early: retrieved {}/{} rows".format(len(rows), total)
                break
            return rows
        if batch == last_batch:
            error = "API returned the same page twice"
            break
        last_batch = batch
        rows.extend(batch)
        offset += len(batch)
        if (total != None and len(rows) >= total) or (total == None and len(batch) < PAGE_SIZE):
            return rows
    print("wazuh: agent {} {} enrichment incomplete ({}); discarding partial inventory".format(agent_id, endpoint, error))
    return []

def is_kubernetes_interface(iface_name):
    """
    Checks if an interface name belongs to Kubernetes networking.
    These interfaces should be excluded as they contain virtual IPs
    for pods/services, not the actual host addresses.
   
    Args:
        iface_name: The name of the network interface
       
    Returns:
        True if the interface is a Kubernetes-related interface, False otherwise
    """
    if not iface_name:
        return False
   
    iface_lower = iface_name.lower()
   
    # Kubernetes IPVS interface - contains all service virtual IPs
    if iface_lower == "kube-ipvs0":
        return True
   
    # Kubernetes local DNS interface
    if iface_lower == "nodelocaldns":
        return True
   
    # Calico CNI interfaces (container networking)
    # These start with "cali" followed by a hash
    if iface_lower.startswith("cali"):
        return True
   
    # Calico VXLAN overlay interface
    if iface_lower.startswith("vxlan.calico"):
        return True
   
    # Flannel CNI interfaces
    if iface_lower.startswith("flannel"):
        return True
    if iface_lower == "cni0":
        return True
   
    # Docker bridge interface
    if iface_lower == "docker0":
        return True
   
    # Kubernetes bridge interfaces
    if iface_lower.startswith("cbr"):
        return True
   
    # Cilium CNI interfaces
    if iface_lower.startswith("cilium"):
        return True
    if iface_lower.startswith("lxc"):
        return True
   
    # Weave CNI interfaces
    if iface_lower.startswith("weave"):
        return True
    if iface_lower.startswith("vethwe"):
        return True
   
    # Generic veth interfaces (container virtual ethernet)
    if iface_lower.startswith("veth"):
        return True
   
    # Kubernetes dummy interfaces
    if iface_lower.startswith("kube-"):
        return True
   
    # IPVS-related interfaces
    if iface_lower.startswith("ipvs"):
        return True
   
    return False

def build_network_interface(network_interfaces_data, network_addresses_data, primary_ip_str):
    """Associate addresses by interface name; never infer a MAC for agent.ip."""
    iface_to_ips = {}
    excluded_ips = {}
    for addr_data in network_addresses_data:
        if type(addr_data) != 'dict':
            continue
        iface_name = str(addr_data.get('iface', '') or '')
        ip_addr_str = routable_ip(addr_data.get('address'))
        if is_kubernetes_interface(iface_name):
            if ip_addr_str:
                excluded_ips[ip_addr_str] = True
            continue
        if ip_addr_str:
            if iface_name not in iface_to_ips:
                iface_to_ips[iface_name] = []
            if ip_addr_str not in iface_to_ips[iface_name]:
                iface_to_ips[iface_name].append(ip_addr_str)

    iface_to_macs = {}
    for interface_data in network_interfaces_data:
        if type(interface_data) != 'dict':
            continue
        iface_name = str(interface_data.get('name', '') or '')
        if is_kubernetes_interface(iface_name):
            continue
        if iface_name not in iface_to_macs:
            iface_to_macs[iface_name] = []
        mac_address_string = interface_data.get('mac')
        if type(mac_address_string) != 'string':
            continue
        for candidate in mac_address_string.split():
            mac = mac_key(candidate)
            if mac and mac != 'ee:ee:ee:ee:ee:ee' and mac not in iface_to_macs[iface_name]:
                iface_to_macs[iface_name].append(mac)

    interfaces = []
    names = list(iface_to_macs)
    for name in iface_to_ips:
        if name not in iface_to_macs:
            names.append(name)
    for name in names:
        ip4s = []
        ip6s = []
        for address in iface_to_ips.get(name, []):
            ip = ip_address(address)
            if ip.version == 4:
                ip4s.append(ip)
            else:
                ip6s.append(ip)
        # An unnamed address row cannot establish an IP-to-MAC relationship.
        macs = iface_to_macs.get(name, []) if name else []
        if macs:
            for mac in macs:
                interfaces.append(NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s))
        elif ip4s or ip6s:
            interfaces.append(NetworkInterface(ipv4Addresses=ip4s, ipv6Addresses=ip6s))
        if not name:
            for mac in iface_to_macs.get(name, []):
                interfaces.append(NetworkInterface(macAddress=mac))

    if not iface_to_ips:
        primary = routable_ip(primary_ip_str)
        if primary and primary not in excluded_ips:
            ip = ip_address(primary)
            interfaces.append(NetworkInterface(
                ipv4Addresses=[ip] if ip.version == 4 else [],
                ipv6Addresses=[ip] if ip.version == 6 else [],
            ))

    return interfaces

def manager_namespace(host):
    """Scope asset ids on the manager the agents are enrolled with.

    Wazuh agent ids are small per-manager ordinals, so nothing about `001` is
    unique outside one manager. Two Wazuh deployments imported into one runZero
    account would otherwise collide on every agent.
    """
    parsed = url_parse(host)
    if parsed and parsed.hostname:
        return parsed.hostname
    # url_parse returns None on a value it cannot parse; fall back to stripping
    # the scheme, any path, and the port by hand.
    bare = host.replace("https://", "").replace("http://", "")
    return bare.split("/")[0].split(":")[0]

def registration_key(date_add):
    """Reduce a registration timestamp to its digits, or "" when there is none.

    `dateAdd` is the agent's registration time and is what separates a recycled
    agent id from the agent that previously held it. Only the digits are kept so
    the id does not move if the API's rendering does -- Wazuh has shipped both
    `2026-01-15T09:00:00Z` and `2026-01-15 09:00:00` for this field, and both
    reduce to the same key here.
    """
    return re_sub(r"[^0-9]", "", str(date_add or ""))

def build_asset_id(namespace, agent_id, date_add):
    """Compose the foreign id for one agent.

    `agent.id` is the stable half: it is assigned once at registration, lives in
    the manager's `client.keys`, and is what every agent-scoped route is
    addressed by -- `/syscollector/{agent_id}/netiface` in this very script. It
    does NOT change when an agent rebalances onto a different cluster worker.
    `node_name` and `manager`, which the previous id was derived from, are the
    fields that DO change on a rebalance: Wazuh documents both as the node the
    agent is currently reporting to.

    `dateAdd` is the disambiguating half. Wazuh allocates agent ids from a
    counter seeded off the highest id in `client.keys`, so once the top-numbered
    agent is purged -- and `<auth><purge>` defaults to `yes` -- the next
    enrollment receives that same id. Registration time separates the new agent
    from the old one.
    """
    reg = registration_key(date_add)
    if reg:
        return "wazuh:{}:agent:{}:{}".format(namespace, agent_id, reg)
    # No registration data to pin the ordinal with. Still namespaced and still
    # deterministic, but this agent's id can be inherited by a later one.
    return "wazuh:{}:agent:{}".format(namespace, agent_id)

def parse_os_info(os_data):
    """
    Parse Wazuh OS information into standardized format.
    """
    if not os_data:
        return "Unknown", "Unknown"
   
    os_name = str(os_data.get('name') or "")
    os_platform = str(os_data.get('platform') or "")
    os_version = str(os_data.get('version') or "")
   
    # Combine name and platform for better identification
    if os_platform and os_platform.lower() != os_name.lower():
        full_os_name = "{} ({})".format(os_name, os_platform)
    else:
        full_os_name = os_name
   
    return full_os_name, os_version

def build_agent_asset(agent, net_interfaces_data, net_addresses_data, namespace):
    """
    Convert one Wazuh agent record into a runZero ImportAsset, or None.

    Args:
        agent: One agent dictionary from the Wazuh API
        net_interfaces_data: The agent's netiface rows, possibly empty.
        net_addresses_data: The agent's netaddr rows, possibly empty.
        namespace: The manager hostname, used to scope every foreign id.
    """
    agent_id = agent.get('id', "")
    if not agent_id:
        print("wazuh: skipping agent with no id: name=" + str(agent.get('name', '')))
        return None
    agent_name = agent.get('name', "")
    node_name = agent.get('node_name', '')

    # Get the primary IP from the main agent data
    agent_ip = agent.get('ip', "")
    agent_status = agent.get('status', "")

    # Parse OS information. The os block is documented as an object but is
    # normalized here so a null or string value costs the fields, not the run.
    os_data = agent.get('os', {})
    if type(os_data) != 'dict':
        os_data = {}
    os_name, os_version = parse_os_info(os_data)

    # Build network interface from the detailed network data
    network_interfaces = build_network_interface(net_interfaces_data, net_addresses_data, agent_ip)

    # Parse timestamps
    first_seen_ts = agent.get('dateAdd', '')
    last_seen_ts = agent.get('lastKeepAlive', '')

    hostnames = clean_hostnames([agent_name], extra=['unknown-agent'])

    # Prepare custom attributes with all available Wazuh data
    custom_attrs = {
        'wazuh_agent_id': str(agent_id),
        'wazuh_agent_name': agent_name,
        'wazuh_agent_status': agent_status,
        'wazuh_agent_version': agent.get('version', ''),
        'wazuh_agent_manager': agent.get('manager', ''),
        'wazuh_node_name': node_name,
        'wazuh_date_add': agent.get('dateAdd', ''),
        'wazuh_last_keep_alive': agent.get('lastKeepAlive', ''),
        'wazuh_group_config_status': agent.get('group_config_status', ''),
        'wazuh_groups': str(agent.get('group', [])),
        'wazuh_merged_sum': agent.get('mergedSum', ''),
        'wazuh_config_sum': agent.get('configSum', ''),
    }

    if first_seen_ts:
        custom_attrs['first_seen_timestamp'] = first_seen_ts
    if last_seen_ts:
        custom_attrs['last_seen_timestamp'] = last_seen_ts

    if os_data:
        custom_attrs.update({
            'os_arch': os_data.get('arch', ''),
            'os_codename': os_data.get('codename', ''),
            'os_major': os_data.get('major', ''),
            'os_minor': os_data.get('minor', ''),
            'os_platform': os_data.get('platform', ''),
            'os_uname': os_data.get('uname', ''),
        })

    date_add = agent.get('dateAdd', '')

    asset_params = {
        'id': build_asset_id(namespace, agent_id, date_add),
        'networkInterfaces': network_interfaces,
        'hostnames': hostnames,
        'os': os_name,
        'osVersion': os_version,
        'customAttributes': to_custom_attributes(custom_attrs),
    }
    for key, value in custom_attrs.items():
        if len(str(value)) > 1023:
            print("wazuh: agent {} attribute {} exceeds 1023 characters; truncating metadata".format(agent_id, key))

    # Leave uncertain roles to runZero fingerprinting.
    device_type = device_type_for_os(os_data)
    if device_type:
        asset_params['deviceType'] = device_type

    # The runtime condition selects the asset type, which is what selects
    # the merge policy; CONFIG["assetTypeBehavior"] holds the reasoning for
    # both grades.
    if registration_key(date_add):
        asset_params['assetType'] = 'agent'
    else:
        asset_params['assetType'] = 'agent-unpinned'
        print("wazuh: agent {} reports no dateAdd; keeping default match behavior, since its ordinal could be reused".format(agent_id))

    return ImportAsset(**asset_params)

def main(**kwargs):
    """
    Main function to retrieve and stream Wazuh asset data.

    Expected kwargs:
        hostname: Wazuh manager hostname or IP address (e.g., wazuh-manager or 10.1.2.3)
        port: Wazuh API port (defaults to 55000)
        username: Wazuh username
        password: Wazuh password

    Agents are enriched and reported one page at a time; nothing is buffered
    across pages and nothing is returned from main.
    """
    require(kwargs, "username", "password")
    wazuh_hostname = get_string(kwargs, "hostname", default="")
    port = get_int(kwargs, "port", default=55000)
    username = get_string(kwargs, "username")
    password = get_string(kwargs, "password")
    # CONFIG defaults are applied by the Console, not by the plain script
    # --kwargs path, so the defaults are repeated here.
    max_pages = get_int(kwargs, "max_pages", default=MAX_PAGES)
    if max_pages < 1:
        fail("wazuh: max_pages must be at least 1")
    rpm = get_int(kwargs, "requests_per_minute", default=240)
    if rpm < 0:
        fail("wazuh: requests_per_minute must not be negative")
    throttle_ms = ((60000 + rpm - 1) // rpm) if rpm > 0 else 0

    # The API base was compiled in as https://<hostname>:<port>, which cannot
    # reach a manager behind a reverse proxy, on a path prefix, or on plain
    # http. An explicit url replaces the composed base entirely; hostname/port
    # stay as the fallback so existing configurations keep working unchanged.
    wazuh_url = (kwargs.get("url") or "").rstrip("/")
    if wazuh_url:
        wazuh_host = wazuh_url
    elif wazuh_hostname:
        wazuh_host = "https://{}:{}".format(wazuh_hostname, port)
    else:
        fail("wazuh: set either the Wazuh API URL or the manager hostname")

    namespace = manager_namespace(wazuh_host)
    print("Connecting to Wazuh at:", wazuh_host)

    # Authenticate with Wazuh
    # authenticate_wazuh ends the task in error itself; a failed login is
    # never a run that reports zero agents.
    token = authenticate_wazuh(wazuh_host, username, password, kwargs)

    # Shared run state. The page walk and the enrichment both read the token
    # from here, so a mid-run re-authentication (Wazuh JWTs default to 900
    # seconds) replaces it for both.
    ctx = {
        "token": token,
        "config": kwargs,
        "reported": 0,
        "throttle_ms": throttle_ms,
    }

    def handle_agents(agents_batch):
        """Enrich and report one page of agents before the next page is
        fetched, so the full agent list is never held in memory."""
        for agent in agents_batch:
            if type(agent) != 'dict':
                print("wazuh: skipping agent record that is not an object")
                continue
            if agent.get('status') != "active":
                continue

            interfaces = []
            addresses = []
            agent_id = agent.get('id')
            if agent_id:
                interfaces = get_agent_network_data(wazuh_host, ctx, agent_id, "netiface", max_pages)
                addresses = get_agent_network_data(wazuh_host, ctx, agent_id, "netaddr", max_pages)

            # report_asset(None) is a no-op returning 0, so a declined record
            # (no id) is counted correctly.
            ctx["reported"] += report_asset(build_agent_asset(agent, interfaces, addresses, namespace))

    print("Retrieving detailed network information for each agent...")
    fetched = get_wazuh_agents(wazuh_host, ctx, max_pages, handle_agents)
    if not fetched:
        print("No agents retrieved from Wazuh")
        return []

    print("Submitted {} Wazuh agents for import; check the task log for validation errors".format(ctx["reported"]))
    return None