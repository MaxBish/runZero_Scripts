load('requests', 'Session')
load('json', json_decode='decode', json_encode='encode')
load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('net', 'ip_address')

DEBUG = False
INSECURE_ALLOWED = True


def is_external_ip(ip_str):
    if not ip_str:
        return False
    if ip_str.startswith('127.') or ip_str == '::1':
        return False
    if ip_str.startswith('169.254.') or ip_str.startswith('fe80:'):
        return False
    return True


def get_node_role(labels):
    if not labels or type(labels) != 'dict':
        return 'worker'
    for key in labels:
        if 'master' in key or 'control-plane' in key:
            return 'master'
    for key in labels:
        if 'worker' in key:
            return 'worker'
    return 'worker'


def get_node_ready_status(conditions):
    if not conditions or type(conditions) != 'list':
        return 'Unknown'
    for condition in conditions:
        if type(condition) == 'dict' and condition.get('type') == 'Ready':
            return condition.get('status', 'Unknown')
    return 'Unknown'


def build_network_interface(addresses):
    ipv4s = []
    ipv6s = []
    for addr_info in addresses:
        if type(addr_info) != 'dict':
            continue
        addr_type = addr_info.get('type', '')
        addr_str = addr_info.get('address', '')
        # Only process IP address types, skip Hostname entries
        if addr_type == 'Hostname' or not addr_str:
            continue
        if not is_external_ip(addr_str):
            continue
        ip_obj = ip_address(addr_str)
        if ip_obj:
            if ip_obj.version == 4:
                ipv4s.append(ip_obj)
            elif ip_obj.version == 6:
                ipv6s.append(ip_obj)
    if not ipv4s and not ipv6s:
        return None
    return NetworkInterface(
        ipv4Addresses=ipv4s[:99],
        ipv6Addresses=ipv6s[:99],
    )


def build_assets(nodes):
    assets = []
    for node in nodes:
        if type(node) != 'dict':
            continue

        metadata = node.get('metadata', {})
        status = node.get('status', {})
        node_info = status.get('nodeInfo', {})
        labels = metadata.get('labels', {})

        uid = metadata.get('uid', '')
        name = metadata.get('name', '')

        if not uid or not name:
            continue

        role = get_node_role(labels)
        ready_status = get_node_ready_status(status.get('conditions', []))

        net_iface = build_network_interface(status.get('addresses', []))
        network_interfaces = [net_iface] if net_iface else []

        # Fall back to older topology label keys if new ones are absent
        region = labels.get('topology.kubernetes.io/region', '') or labels.get('failure-domain.beta.kubernetes.io/region', '')
        zone = labels.get('topology.kubernetes.io/zone', '') or labels.get('failure-domain.beta.kubernetes.io/zone', '')
        arch = node_info.get('architecture', '') or labels.get('kubernetes.io/arch', '')

        # Note: physical hardware details (CPU model, RAM, serial number) are not
        # exposed by the Kubernetes/OpenShift API. systemUUID maps to the SMBIOS
        # UUID and can help runZero correlate nodes with scan-discovered assets.
        system_uuid = node_info.get('systemUUID', '')
        machine_id = node_info.get('machineID', '')

        node_attrs = {
            'openshift_node_name':          name,
            'openshift_role':               role,
            'openshift_ready_status':       ready_status,
            'openshift_kernel_version':     node_info.get('kernelVersion', ''),
            'openshift_os_image':           node_info.get('osImage', ''),
            'openshift_container_runtime':  node_info.get('containerRuntimeVersion', ''),
            'openshift_kubelet_version':    node_info.get('kubeletVersion', ''),
            'openshift_kube_proxy_version': node_info.get('kubeProxyVersion', ''),
            'openshift_architecture':       arch,
            'openshift_region':             region,
            'openshift_zone':               zone,
            'openshift_system_uuid':        system_uuid,
            'openshift_machine_id':         machine_id,
        }

        if DEBUG:
            all_ips = []
            for iface in network_interfaces:
                for ip in iface.ipv4Addresses:
                    all_ips.append(str(ip))
                for ip in iface.ipv6Addresses:
                    all_ips.append(str(ip))
            ip_summary = ', '.join(all_ips) if all_ips else 'none'
            print("Node: {} | Role: {} | IPs: {} | Ready: {}".format(name, role, ip_summary, ready_status))

        assets.append(ImportAsset(
            id=uid,
            hostnames=[name],
            networkInterfaces=network_interfaces,
            os=node_info.get('operatingSystem', 'linux'),
            osVersion=node_info.get('osImage', ''),
            manufacturer='Red Hat',
            model='OpenShift Node',
            deviceType='Server',
            tags=['openshift', 'node', role],
            customAttributes=node_attrs,
        ))

    return assets


def fetch_nodes(session, base_url):
    nodes = []
    url = '{}/api/v1/nodes'.format(base_url)

    while url:
        resp = session.get(url)
        if not resp or resp.status_code != 200:
            print("ERROR: Failed to fetch nodes (status {})".format(
                resp.status_code if resp else 'no response'
            ))
            return []

        body = json_decode(resp.body)
        items = body.get('items', [])
        nodes.extend(items)

        if DEBUG:
            print("Fetched {} node(s) (running total: {})".format(len(items), len(nodes)))

        # Handle pagination via continue token
        continue_token = body.get('metadata', {}).get('continue', '')
        if continue_token:
            url = '{}/api/v1/nodes?continue={}'.format(base_url, continue_token)
        else:
            url = None

    return nodes


def main(*args, **kwargs):
    """
    OpenShift custom integration: syncs cluster nodes into runZero.

    Credentials — set access_secret to a JSON blob:
      {
        "base_url":      "https://api.cluster.example.com:6443",
        "access_secret": "<service-account-bearer-token>"
      }
    """
    secret = json_decode(kwargs.get('access_secret', '{}'))
    base_url = secret.get('base_url', '').rstrip('/')
    token = secret.get('access_secret', '')

    if not base_url or not token:
        print("ERROR: Missing base_url or access_secret in credential JSON")
        return []

    session = Session(insecure_skip_verify=INSECURE_ALLOWED)
    session.headers.set('Accept', 'application/json')
    session.headers.set('Authorization', 'Bearer {}'.format(token))

    # Verify connectivity
    ver_resp = session.get('{}/version'.format(base_url))
    if ver_resp and ver_resp.status_code == 200:
        ver_data = json_decode(ver_resp.body)
        print("Connected to cluster: {}".format(ver_data.get('gitVersion', 'unknown')))
    else:
        print("WARNING: /version check failed for {}".format(base_url))

    nodes = fetch_nodes(session, base_url)
    if not nodes:
        print("No nodes returned from API")
        return []

    print("Fetched {} node(s) from OpenShift cluster".format(len(nodes)))
    assets = build_assets(nodes)

    if DEBUG:
        print("=" * 60)
        print("Total assets ready for import: {}".format(len(assets)))

    return assets
