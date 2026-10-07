CONFIG = {
    "id": "vmware-vcf-vsphere",
    "name": "VMware VCF and vSphere",
    "type": "inbound",
    "description": "Imports VCF infrastructure or vSphere virtual machines and hosts through REST APIs.",
    "version": "1",
    "maturity": "alpha",
    "minVersion": "5.1.260818.0",
    "matchBehavior": "no-ip-break no-name-break",
    "assetTypeBehavior": {
        "esxi-host": "no-id-match no-id-break",
        "management-appliance": "no-id-match no-id-break",
    },
    "maxPages": 10000,
    "params": [
        {"key": "mode", "label": "API", "type": "enum", "options": ["vcf", "vsphere"], "default": "vcf"},
        {"key": "url", "label": "SDDC Manager or vCenter URL", "type": "url", "required": True},
        {"key": "source_scope", "label": "Stable source namespace", "type": "string", "required": True, "pattern": "[a-zA-Z0-9._-]+", "description": "Unique label for this SDDC Manager or vCenter installation. Keep it unchanged between polls."},
        {"key": "username", "label": "Username", "type": "secret", "required": True},
        {"key": "password", "label": "Password", "type": "secret", "required": True},
        {"key": "guest_details", "label": "Read VMware Tools guest data", "type": "bool", "default": True},
        {"key": "vapi_metadata", "label": "Read vAPI package metadata", "type": "bool", "default": True},
        {"key": "cluster_ids", "label": "vSphere cluster IDs", "type": "string", "description": "Optional comma-separated cluster IDs to restrict inventory."},
    ],
    "includes": {"tls_": OPTIONS_TLS, "http_": OPTIONS_HTTP},
}

load("runzero.types", "ImportAsset", "Software", "to_custom_attributes")
load("coerce", "as_text", "as_dict", "as_list", "as_int", "dicts", "dedupe")
load("net", "clean_hostnames", "network_interface")
load("kwargs", "require", "get_string", "get_bool", "get_list", "get_url_base", "get_http_options")
load("http", "get_json", "post_json", "basic", "bearer", "url_encode", "url_parse", http_delete="delete")

def vm_asset(scope, vm_id, detail, guest, guest_interfaces, context):
    identity = as_dict(detail.get("identity"))
    instance_uuid = as_text(identity.get("instance_uuid")).strip().lower()
    if not instance_uuid:
        print("Skipping VM without instance UUID")
        return None
    interfaces = []
    for nic in dicts(as_dict(detail.get("nics")).values()):
        interface = network_interface(mac=as_text(nic.get("mac_address")))
        if interface:
            interfaces.append(interface)
    for nic in dicts(guest_interfaces):
        addresses = [as_text(address.get("ip_address")) for address in dicts(as_dict(nic.get("ip")).get("ip_addresses"))]
        interface = network_interface(mac=as_text(nic.get("mac_address")), ips=addresses)
        if interface:
            interfaces.append(interface)
    interface = network_interface(ips=[as_text(guest.get("ip_address"))])
    if interface:
        interfaces.append(interface)
    attributes = dict(context)
    attributes.update({
        "vmware.vm_id": vm_id,
        "vmware.vm_name": as_text(detail.get("name")),
        "vmware.instance_uuid": instance_uuid,
        "vmware.bios_uuid": as_text(identity.get("bios_uuid")),
        "vmware.power_state": as_text(detail.get("power_state")),
        "vmware.configured_guest_os": as_text(detail.get("guest_OS")),
        "vmware.hardware_version": as_text(as_dict(detail.get("hardware")).get("version")),
        "vmware.cpu_count": as_dict(detail.get("cpu")).get("count"),
        "vmware.memory_mib": as_dict(detail.get("memory")).get("size_MiB"),
    })
    return ImportAsset(
        id="vmware:vsphere:{}:vm:{}".format(scope, instance_uuid),
        assetType="virtual-machine",
        hostnames=clean_hostnames([as_text(guest.get("host_name"))]),
        networkInterfaces=interfaces,
        os=as_text(as_dict(guest.get("full_name")).get("default_message")),
        manufacturer="VMware",
        model="Virtual Machine",
        customAttributes=to_custom_attributes(attributes),
    )

def read_api(base, path, options, params=None, optional=False):
    data, err = get_json(base + path, params=params, retries=2, **options)
    if err:
        if optional and (err.startswith("status 404:") or err.startswith("status 503:") or err.startswith("status 403:")):
            print("Optional enrichment unavailable: {}".format(path))
            return None
        status = err.split(":", 1)[0] if err.startswith("status ") else "transport or decoding error"
        fail("VMware request failed: {}: {} (check connectivity, permissions, session lifetime, and API limits)".format(path, status))
    return data

def vcf_records(base, path, options):
    data = read_api(base, path, options)
    if type(data) != "dict" or type(data.get("elements")) != "list":
        fail("Expected VCF elements array: {}".format(path))
    metadata = as_dict(data.get("pageMetadata"))
    if as_int(metadata.get("totalPages")) > 1 or as_int(metadata.get("totalElements")) > len(data["elements"]):
        fail("VCF returned a partial collection; paging parameters require confirmation: {}".format(path))
    return dicts(data["elements"])

def software_entry(product, version, vendor="VMware"):
    return Software(
        id="vmware:{}:{}".format(product, version),
        vendor=vendor,
        product=product,
        version=version,
    )

def host_software(host):
    software = []
    version = as_text(host.get("esxiVersion"))
    if version:
        software.append(software_entry("ESXi", version))
    info = as_dict(host.get("softwareInfo"))
    for component_id, component in as_dict(info.get("components")).items():
        component = as_dict(component)
        details = as_dict(component.get("details"))
        product = as_text(details.get("displayName")) or as_text(component_id)
        version = as_text(component.get("version"))
        if product and version:
            software.append(software_entry(product, version, as_text(details.get("vendor"))))
    addon = as_dict(info.get("addOn"))
    if as_text(addon.get("name")) and as_text(addon.get("version")):
        software.append(software_entry(as_text(addon["name"]), as_text(addon["version"]), as_text(addon.get("vendor"))))
    return software

def infrastructure_asset(scope, kind, hostname, ips, interfaces, attributes, product, version="", software=None, manufacturer="VMware", model="", serial=""):
    names = clean_hostnames([hostname])
    if not names:
        print("Skipping infrastructure record without usable hostname")
        return None
    interface = network_interface(ips=ips)
    if interface:
        interfaces.append(interface)
    if software == None:
        software = [software_entry(product, version)] if version else []
    attributes = dict(attributes)
    attributes["vmware.serial_number"] = serial
    return ImportAsset(
        id="vmware:{}:{}:{}".format(scope, kind, names[0].lower()),
        assetType=kind,
        hostnames=names,
        networkInterfaces=interfaces,
        os="VMware ESXi" if kind == "esxi-host" else "",
        osVersion=version if kind == "esxi-host" else "",
        manufacturer=manufacturer,
        model=model or product,
        software=software,
        customAttributes=to_custom_attributes(attributes),
    )

def import_vcf(base, scope, options):
    domains = {}
    seen = {}
    total = 0
    for domain in vcf_records(base, "/v1/domains", options):
        domain_id = as_text(domain.get("id"))
        domains[domain_id] = as_text(domain.get("name"))
        for vcenter in dicts(domain.get("vcenters")):
            hostname = as_text(vcenter.get("fqdn"))
            if not hostname or hostname.lower() in seen:
                continue
            asset = infrastructure_asset(scope, "management-appliance", hostname, [], [], {
                "vmware.product": "vCenter Server",
                "vmware.domain_id": domain_id,
                "vmware.domain_name": domains[domain_id],
                "vmware.source_id": as_text(vcenter.get("id")),
            }, "vCenter Server")
            total += report_asset(asset)
            seen[hostname.lower()] = True
    clusters = {}
    for cluster in vcf_records(base, "/v1/clusters", options):
        clusters[as_text(cluster.get("id"))] = as_text(cluster.get("name"))
    for host in vcf_records(base, "/v1/hosts", options):
        hostname = as_text(host.get("fqdn"))
        if not hostname or hostname.lower() in seen:
            continue
        interfaces = []
        for nic in dicts(host.get("physicalNics")):
            interface = network_interface(mac=as_text(nic.get("macAddress")))
            if interface:
                interfaces.append(interface)
        addresses = [as_text(address.get("ipAddress")) for address in dicts(host.get("ipAddresses"))]
        domain = as_dict(host.get("domain"))
        cluster = as_dict(host.get("cluster"))
        attributes = {
            "vmware.source_id": as_text(host.get("id")),
            "vmware.status": as_text(host.get("status")),
            "vmware.domain_id": as_text(domain.get("id")),
            "vmware.domain_name": as_text(domain.get("name")) or domains.get(as_text(domain.get("id")), ""),
            "vmware.cluster_id": as_text(cluster.get("id")),
            "vmware.cluster_name": as_text(cluster.get("name")) or clusters.get(as_text(cluster.get("id")), ""),
        }
        total += report_asset(infrastructure_asset(
            scope, "esxi-host", hostname, addresses, interfaces, attributes, "ESXi",
            version=as_text(host.get("esxiVersion")), software=host_software(host),
            manufacturer=as_text(host.get("hardwareVendor")), model=as_text(host.get("hardwareModel")),
            serial=as_text(host.get("serialNumber")),
        ))
        seen[hostname.lower()] = True
    for manager in vcf_records(base, "/v1/sddc-managers", options):
        hostname = as_text(manager.get("fqdn"))
        if not hostname or hostname.lower() in seen:
            continue
        total += report_asset(infrastructure_asset(scope, "management-appliance", hostname,
            [as_text(manager.get("ipAddress"))], [], {"vmware.product": "SDDC Manager", "vmware.source_id": as_text(manager.get("id"))},
            "SDDC Manager", version=as_text(manager.get("version"))))
        seen[hostname.lower()] = True
    for cluster in vcf_records(base, "/v1/nsxt-clusters", options):
        for node in dicts(cluster.get("nodes")):
            hostname = as_text(node.get("fqdn"))
            if not hostname or hostname.lower() in seen:
                continue
            total += report_asset(infrastructure_asset(scope, "management-appliance", hostname,
                [as_text(node.get("ipAddress"))], [], {
                    "vmware.product": "NSX Manager", "vmware.nsx_cluster_id": as_text(cluster.get("id")),
                    "vmware.source_id": as_text(node.get("id")),
                    "vmware.domain_ids": [as_text(domain.get("id")) for domain in dicts(cluster.get("domains"))],
                }, "NSX Manager", version=as_text(cluster.get("version"))))
            seen[hostname.lower()] = True
    return total

def sphere_list(base, path, options, params=None, limit=None):
    data = read_api(base, path, options, params=params)
    if type(data) != "list":
        fail("Expected vSphere array: {}".format(path))
    if limit != None and len(data) > limit:
        fail("vSphere inventory exceeded documented limit: {}".format(path))
    return data

def import_vsphere(base, scope, options, kwargs):
    filters = {}
    cluster_ids = get_list(kwargs, "cluster_ids", default=[])
    if cluster_ids:
        filters["clusters"] = cluster_ids
    hosts = dicts(sphere_list(base, "/api/vcenter/host", options, params=filters, limit=2500))
    total = 0
    seen = {}
    for host in hosts:
        hostname = as_text(host.get("name"))
        if hostname and hostname.lower() not in seen:
            total += report_asset(infrastructure_asset(scope, "esxi-host", hostname, [], [], {
                "vmware.host_id": as_text(host.get("host")),
                "vmware.connection_state": as_text(host.get("connection_state")),
                "vmware.power_state": as_text(host.get("power_state")),
            }, "ESXi"))
            seen[hostname.lower()] = True
    vm_seen = {}
    guard = pager("vSphere VM details")
    for summary in dicts(sphere_list(base, "/api/vcenter/vm", options, params=filters, limit=4000)):
        guard.next()
        vm_id = as_text(summary.get("vm"))
        if not vm_id:
            print("Skipping VM summary without resource ID")
            continue
        path = "/api/vcenter/vm/" + url_encode(vm_id)
        detail = read_api(base, path, options, optional=True)
        if detail == None:
            continue
        if type(detail) != "dict":
            print("Skipping malformed VM detail")
            continue
        guest = {}
        guest_interfaces = []
        if get_bool(kwargs, "guest_details", default=True) and detail.get("power_state") == "POWERED_ON":
            guest = as_dict(read_api(base, path + "/guest/identity", options, optional=True))
            guest_interfaces = as_list(read_api(base, path + "/guest/networking/interfaces", options, optional=True))
        asset = vm_asset(scope, vm_id, detail, guest, guest_interfaces, {"vmware.vcenter": base})
        if asset and asset.id not in vm_seen:
            total += report_asset(asset)
            vm_seen[asset.id] = True
    attributes = {"vmware.product": "vCenter Server"}
    version = as_dict(read_api(base, "/api/appliance/system/version", options, optional=True))
    attributes["vmware.build"] = as_text(version.get("build"))
    if get_bool(kwargs, "vapi_metadata", default=True):
        for kind in ["component", "package"]:
            metadata = read_api(base, "/api/vapi/metadata/metamodel/" + kind, options, optional=True)
            attributes["vmware.vapi_" + kind + "s"] = sorted(dedupe([as_text(item) for item in as_list(metadata) if type(item) == "string" and item]))
    total += report_asset(infrastructure_asset(scope, "management-appliance", url_parse(base).hostname, [], [], attributes,
        "vCenter Server", version=as_text(version.get("version"))))
    return total

def main(*args, **kwargs):
    require(kwargs, "url", "source_scope", "username", "password")
    base = get_url_base(kwargs)
    parsed = url_parse(base)
    if not parsed or parsed.scheme != "https" or parsed.username or parsed.password:
        fail("Use an HTTPS base URL without embedded credentials")
    scope = get_string(kwargs, "source_scope")
    mode = get_string(kwargs, "mode", default="vcf")
    headers = {"Accept": "application/json"}
    if mode == "vsphere":
        headers["Authorization"] = basic(get_string(kwargs, "username"), get_string(kwargs, "password"))
        token, err = post_json(base + "/api/session", retries=0, **get_http_options(kwargs, headers=headers))
        if err or type(token) != "string" or not token:
            fail("vSphere authentication failed; verify username, password, and endpoint")
        options = get_http_options(kwargs, headers={"Accept": "application/json", "vmware-api-session-id": token})
        total = import_vsphere(base, scope, options, kwargs)
        response = http_delete(base + "/api/session", **options)
        if response.status_code != 204:
            print("vSphere session cleanup was unsuccessful")
    elif mode == "vcf":
        token, err = post_json(base + "/v1/tokens", json={"username": get_string(kwargs, "username"), "password": get_string(kwargs, "password")},
            retries=0, **get_http_options(kwargs, headers=headers))
        access_token = as_text(as_dict(token).get("accessToken"))
        if err or not access_token:
            fail("VCF authentication failed; verify username, password, and endpoint")
        options = get_http_options(kwargs, headers={"Accept": "application/json", "Authorization": bearer(access_token)})
        total = import_vcf(base, scope, options)
        refresh_token = as_text(as_dict(as_dict(token).get("refreshToken")).get("id"))
        if refresh_token:
            response = http_delete(base + "/v1/tokens/refresh-token", json=refresh_token, **get_http_options(kwargs, headers=headers))
            if response.status_code != 204:
                print("VCF refresh-token cleanup was unsuccessful")
    else:
        fail("mode must be vcf or vsphere")
    print("Reported {} VMware assets".format(total))
    return None