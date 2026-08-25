CONFIG = {
    "id": "runzero-bmc-helix-cmdb-outbound",
    "name": "BMC Helix CMDB Outbound",
    "type": "outbound",
    "description": "Exports runZero assets and upserts CI records into BMC Helix CMDB.",
    "version": "26072000",
    "minVersion": "5.1.0",
    "params": [
        {
            "key": "runzero_export_token",
            "label": "runZero export token",
            "type": "secret",
            "required": True,
        },
        {
            "key": "helix_client_id",
            "label": "Helix client ID",
            "type": "string",
            "required": True,
        },
        {
            "key": "helix_client_secret",
            "label": "Helix client secret",
            "type": "secret",
            "required": True,
        },
        {
            "key": "runzero_console_url",
            "label": "runZero console URL",
            "type": "url",
            "required": True,
            "default": "https://console.runzero.com",
        },
        {
            "key": "runzero_search",
            "label": "runZero search filter",
            "type": "string",
            "required": False,
            "default": "alive:t",
        },
        {
            "key": "helix_api_base",
            "label": "Helix API base URL",
            "type": "url",
            "required": True,
        },
        {
            "key": "helix_dataset_id",
            "label": "Helix dataset ID",
            "type": "string",
            "required": True,
            "default": "BMC.ASSET.SANDBOX",
        },
        {
            "key": "auth_login_path",
            "label": "Helix auth login path",
            "type": "string",
            "required": False,
            "default": "/api/rx/authentication/oauth/token",
        },
        {
            "key": "cmdb_query_path",
            "label": "CMDB query path",
            "type": "string",
            "required": False,
            "default": "/api/cmdb/v1/instance/{datasetId}/{classPath}",
        },
        {
            "key": "cmdb_create_path",
            "label": "CMDB create path",
            "type": "string",
            "required": False,
            "default": "/api/cmdb/v1/instance/{datasetId}/{classPath}",
        },
        {
            "key": "cmdb_update_path",
            "label": "CMDB update path",
            "type": "string",
            "required": False,
            "default": "/api/cmdb/v1/instance/{datasetId}/{classPath}/{instanceId}",
        },
        {
            "key": "ast_attributes_path",
            "label": "AST attributes path",
            "type": "string",
            "required": False,
            "default": "/api/arsys/v1/entry/AST:Attributes",
        },
        {
            "key": "post_ast_attributes",
            "label": "Post AST attributes record",
            "type": "bool",
            "required": False,
            "default": False,
        },
        {
            "key": "runzero_timeout",
            "label": "runZero timeout seconds",
            "type": "int",
            "required": False,
            "default": 600,
            "min": 1,
            "max": 3600,
        },
        {
            "key": "helix_timeout",
            "label": "Helix timeout seconds",
            "type": "int",
            "required": False,
            "default": 120,
            "min": 1,
            "max": 3600,
        },
        {
            "key": "max_log_body",
            "label": "Max logged body characters",
            "type": "int",
            "required": False,
            "default": 800,
            "min": 0,
            "max": 20000,
        },
        {
            "key": "system_environment",
            "label": "Helix system environment",
            "type": "string",
            "required": False,
            "default": "Production",
        },
        {
            "key": "ip_category",
            "label": "IP category",
            "type": "string",
            "required": False,
            "default": "Network",
        },
        {
            "key": "ip_type",
            "label": "IP type",
            "type": "string",
            "required": False,
            "default": "Address",
        },
        {
            "key": "ip_item",
            "label": "IP item",
            "type": "string",
            "required": False,
            "default": "IP Address",
        },
        {
            "key": "os_category",
            "label": "OS category",
            "type": "string",
            "required": False,
            "default": "Software",
        },
        {
            "key": "os_type",
            "label": "OS type",
            "type": "string",
            "required": False,
            "default": "Operating System software",
        },
        {
            "key": "os_item",
            "label": "OS item",
            "type": "string",
            "required": False,
            "default": "Operating System",
        },
        {
            "key": "lan_category",
            "label": "LAN category",
            "type": "string",
            "required": False,
            "default": "Network",
        },
        {
            "key": "lan_type",
            "label": "LAN type",
            "type": "string",
            "required": False,
            "default": "Address",
        },
        {
            "key": "lan_item",
            "label": "LAN item",
            "type": "string",
            "required": False,
            "default": "MAC Address",
        },
        {
            "key": "hardware_category",
            "label": "Hardware category",
            "type": "string",
            "required": False,
            "default": "Hardware",
        },
        {
            "key": "hardware_type",
            "label": "Hardware type",
            "type": "string",
            "required": False,
            "default": "Hardware",
        },
        {
            "key": "hardware_item",
            "label": "Hardware item",
            "type": "string",
            "required": False,
            "default": "Management controller",
        },
    ],
    "includes": {
        "rz_tls_": OPTIONS_TLS,
        "rz_http_": OPTIONS_HTTP,
        "helix_tls_": OPTIONS_TLS,
        "helix_http_": OPTIONS_HTTP,
    },
}

load('json', json_encode='encode', json_decode='decode')
load('http', http_get='get', http_post='post', 'url_encode', 'basic')
load('kwargs', 'get_bool', 'get_http_options', 'get_int', 'get_string', 'require')

RUNZERO_EXPORT_PATH = '/api/v1.0/export/org/assets.json'

CLASS_FIELD_MAPPINGS = {
    'BMC_ComputerSystem': {
        'Name': ['fqdn', 'fqdnHostname', 'hostname', 'name'],
        'Short Description': ['hostname', 'name'],
        'SerialNumber': ['serialNumber', 'serial', 'serial_number'],
        'Status': '__status__',
        'SystemEnvironment': '__system_environment__',
        'Model': ['productName', 'model'],
        'ManufacturerName': ['manufacturer'],
        'LastScanDate': '__last_scan_date__',
        'isVirtual': '__is_virtual__',
        'HostName': ['hostname', 'name'],
        'Domain': '__domain__',
        'TotalPhysicalMemory': '__total_physical_memory__',
    },
    'BMC_IPEndpoint': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'Category': '__ip_category__',
        'Type': '__ip_type__',
        'Item': '__ip_item__',
    },
    'BMC_OperatingSystem': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'Category': '__os_category__',
        'Type': '__os_type__',
        'Item': '__os_item__',
        'Model': ['productName', 'model'],
        'VersionNumber': ['osVersion', 'os_version', 'osBuild', 'build'],
        'PatchNumber': ['servicePack', 'patchNumber', 'patch', 'hotfix'],
        'OSType': ['osType', 'platform', 'osFamily'],
    },
    'BMC_LANEndpoint': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'Category': '__lan_category__',
        'Type': '__lan_type__',
        'Item': '__lan_item__',
        'Address': ['mac', 'macAddress', 'mac_address'],
    },
    'BMC_HardwareSystemComponent': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'SerialNumber': ['serialNumber', 'serial', 'serial_number'],
        'Category': '__hardware_category__',
        'Type': '__hardware_type__',
        'Item': '__hardware_item__',
        'Model': ['productName', 'model'],
        'VersionNumber': ['osVersion', 'os_version', 'version', 'firmwareVersion'],
        'ManufacturerName': ['manufacturer'],
    },
}

LIFECYCLE_TO_BMC_STATUS = {
    'planned for introduction': 'Reserved',
    'project forecast': 'Reserved',
    'implemented': 'Being Assembled',
    'project readiness': 'Being Assembled',
    'live in production': 'Deployed',
    'handover completed': 'Deployed',
    'planned to remove': 'Down',
    'decommissioned': 'End of Life',
}

DEFAULT_CLASS_NAMES = [
    'BMC_ComputerSystem',
    'BMC_IPEndpoint',
    'BMC_OperatingSystem',
    'BMC_LANEndpoint',
    'BMC_HardwareSystemComponent',
]

def _log(message):
    print('[HELIX-CMDB-OUTBOUND] {}'.format(str(message)))

def _text(value):
    if value == None:
        return ''
    if type(value) == 'dict' or type(value) == 'list':
        return json_encode(value)
    return str(value)

def _trim(text, max_len):
    value = _text(text)
    if len(value) <= max_len:
        return value
    return value[:max_len]

def _lower(value):
    return _text(value).strip().lower()

def _safe_json_decode(body):
    payload_text = _text(body).strip()
    if payload_text == '':
        return None
    return json_decode(payload_text)

def _join_url(base_url, path):
    return base_url.rstrip('/') + '/' + path.lstrip('/')

def _first_non_empty(record, keys):
    if type(record) != 'dict':
        return ''
    for key in keys:
        if key not in record:
            continue
        value = _text(record.get(key)).strip()
        if value != '':
            return value
    return ''

def _as_list(value):
    if value == None:
        return []
    if type(value) == 'list':
        return value
    return [value]

def _candidate_hostnames(asset):
    values = []
    primary = _first_non_empty(asset, ['hostname', 'name', 'fqdn'])
    if primary != '':
        values.append(primary)

    for key in ['hostnames', 'names']:
        for item in _as_list(asset.get(key)):
            text = _text(item).strip()
            if text != '':
                values.append(text)

    deduped = []
    seen = {}
    for value in values:
        lowered = value.lower()
        if lowered in seen:
            continue
        seen[lowered] = True
        deduped.append(value)
    return deduped

def _candidate_serials(asset):
    values = []
    primary = _first_non_empty(asset, ['serial', 'serialNumber'])
    if primary != '':
        values.append(primary)

    for key in ['serial_numbers', 'serialNumbers']:
        for item in _as_list(asset.get(key)):
            text = _text(item).strip()
            if text != '':
                values.append(text)

    deduped = []
    seen = {}
    for value in values:
        if value in seen:
            continue
        seen[value] = True
        deduped.append(value)
    return deduped

def _candidate_ips(asset):
    values = []
    for key in ['addresses', 'ipAddresses', 'ip_addresses', 'ips']:
        for item in _as_list(asset.get(key)):
            text = _text(item).strip()
            if text != '':
                values.append(text)

    primary = _first_non_empty(asset, ['ip', 'ipAddress', 'address'])
    if primary != '':
        values.append(primary)

    deduped = []
    seen = {}
    for value in values:
        if value in seen:
            continue
        seen[value] = True
        deduped.append(value)
    return deduped

def _candidate_macs(asset):
    values = []
    for key in ['macs', 'macAddresses', 'mac_addresses']:
        for item in _as_list(asset.get(key)):
            text = _text(item).strip()
            if text != '':
                values.append(text)

    primary = _first_non_empty(asset, ['mac', 'macAddress', 'mac_address'])
    if primary != '':
        values.append(primary)

    deduped = []
    seen = {}
    for value in values:
        lowered = value.lower()
        if lowered in seen:
            continue
        seen[lowered] = True
        deduped.append(value)
    return deduped

def _ci_name(asset):
    hostnames = _candidate_hostnames(asset)
    if len(hostnames) > 0:
        return hostnames[0]

    ips = _candidate_ips(asset)
    if len(ips) > 0:
        return ips[0]

    serials = _candidate_serials(asset)
    if len(serials) > 0:
        return serials[0]

    return _first_non_empty(asset, ['id', 'asset_id', 'uuid'])

def _ci_description(asset):
    return _first_non_empty(asset, ['hostname', 'name', 'description', 'os'])

def _status_from_asset(asset):
    explicit = _first_non_empty(asset, ['status_bmc', 'bmcStatus'])
    if explicit != '':
        return explicit

    source = _first_non_empty(asset, ['lifecycle', 'lifeCycle', 'status'])
    source_lower = _lower(source)
    if source_lower == '':
        return 'Deployed'

    for key, mapped in LIFECYCLE_TO_BMC_STATUS.items():
        if key in source_lower:
            return mapped

    if source in ['Reserved', 'Being Assembled', 'Deployed', 'Down', 'End of Life', 'Ordered']:
        return source
    return 'Deployed'

def _domain_from_asset(asset):
    fqdn = _first_non_empty(asset, ['fqdn', 'dnsName', 'dns_name', 'name'])
    if fqdn == '' or '.' not in fqdn:
        return ''
    parts = fqdn.split('.')
    if len(parts) < 2:
        return ''
    return '.'.join(parts[1:])

def _last_scan_date(asset):
    return _first_non_empty(asset, ['lastSeen', 'last_seen', 'lastSeenAt', 'updatedAt', 'updated_at', 'scanTime'])

def _is_virtual(asset):
    value = _lower(_first_non_empty(asset, ['isVirtual', 'virtual', 'is_vm', 'isVirtualMachine']))
    if value in ['1', 'true', 'yes', 'y', 'on']:
        return 'Yes'
    if value in ['0', 'false', 'no', 'n', 'off']:
        return 'No'

    virt_hint = _lower(_first_non_empty(asset, ['virtualizationType', 'hypervisor', 'platform']))
    if virt_hint != '' and virt_hint not in ['bare metal', 'physical']:
        return 'Yes'
    return ''

def _total_physical_memory(asset):
    return _first_non_empty(asset, ['totalPhysicalMemory', 'memoryTotal', 'totalMemory', 'ram'])

def _resolve_mapping_token(asset, token, config):
    if token == '__status__':
        return _status_from_asset(asset)
    if token == '__ci_name__':
        return _ci_name(asset)
    if token == '__ci_description__':
        return _ci_description(asset)
    if token == '__system_environment__':
        return config.get('system_environment', 'Production')
    if token == '__last_scan_date__':
        return _last_scan_date(asset)
    if token == '__is_virtual__':
        return _is_virtual(asset)
    if token == '__domain__':
        return _domain_from_asset(asset)
    if token == '__total_physical_memory__':
        return _total_physical_memory(asset)
    if token == '__ip_category__':
        return config.get('ip_category', 'Network')
    if token == '__ip_type__':
        return config.get('ip_type', 'Address')
    if token == '__ip_item__':
        return config.get('ip_item', 'IP Address')
    if token == '__os_category__':
        return config.get('os_category', 'Software')
    if token == '__os_type__':
        return config.get('os_type', 'Operating System software')
    if token == '__os_item__':
        return config.get('os_item', 'Operating System')
    if token == '__lan_category__':
        return config.get('lan_category', 'Network')
    if token == '__lan_type__':
        return config.get('lan_type', 'Address')
    if token == '__lan_item__':
        return config.get('lan_item', 'MAC Address')
    if token == '__hardware_category__':
        return config.get('hardware_category', 'Hardware')
    if token == '__hardware_type__':
        return config.get('hardware_type', 'Hardware')
    if token == '__hardware_item__':
        return config.get('hardware_item', 'Management controller')
    return ''

def _resolve_field_spec(asset, spec, config):
    if type(spec) == 'string':
        if spec.startswith('__') and spec.endswith('__'):
            return _resolve_mapping_token(asset, spec, config)
        return _first_non_empty(asset, [spec])
    if type(spec) == 'list':
        return _first_non_empty(asset, spec)
    return ''

def _should_route_to_class(asset, class_name):
    if class_name == 'BMC_ComputerSystem':
        return True
    if class_name == 'BMC_OperatingSystem':
        return _first_non_empty(asset, ['os', 'osVersion', 'os_version']) != ''
    if class_name == 'BMC_IPEndpoint':
        return len(_candidate_ips(asset)) > 0
    if class_name == 'BMC_LANEndpoint':
        return len(_candidate_macs(asset)) > 0
    if class_name == 'BMC_HardwareSystemComponent':
        return _first_non_empty(asset, ['serial', 'serialNumber', 'serial_number', 'manufacturer', 'model']) != ''
    return False

def _routed_classes(asset, class_names):
    routed = []
    for class_name in class_names:
        if _should_route_to_class(asset, class_name):
            routed.append(class_name)
    if len(routed) == 0:
        routed.append('BMC_ComputerSystem')
    return routed

def _map_asset_to_helix_payload(asset, class_name, dataset_id, config):
    payload = {
        'className': class_name,
        'datasetId': dataset_id,
        'attributes': {},
    }
    attrs = payload['attributes']
    class_map = CLASS_FIELD_MAPPINGS.get(class_name)
    if type(class_map) == 'dict':
        for target_key, field_spec in class_map.items():
            value = _resolve_field_spec(asset, field_spec, config)
            value_text = _text(value).strip()
            if value_text == '':
                continue
            attrs[target_key] = value_text

    hostnames = _candidate_hostnames(asset)
    serials = _candidate_serials(asset)
    macs = _candidate_macs(asset)
    if len(hostnames) > 0 and 'Name' not in attrs:
        attrs['Name'] = hostnames[0]
    if len(serials) > 0 and 'SerialNumber' not in attrs:
        attrs['SerialNumber'] = serials[0]
    if class_name == 'BMC_LANEndpoint' and len(macs) > 0 and 'Address' not in attrs:
        attrs['Address'] = macs[0]
    return payload

def _class_path(class_name):
    text = _text(class_name).strip()
    if text == '':
        return ''
    if '/' in text:
        return text
    return 'BMC.CORE/{}'.format(text)

def _helix_headers(token):
    return {
        'Authorization': 'Bearer {}'.format(token),
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    }

def _helix_endpoint(config, endpoint_key, class_name, dataset_id, instance_id=''):
    path = config.get(endpoint_key, '')
    path = path.replace('{className}', class_name)
    path = path.replace('{classPath}', _class_path(class_name))
    path = path.replace('{datasetId}', dataset_id)
    path = path.replace('{instanceId}', instance_id)
    return _join_url(config.get('helix_api_base', ''), path)

def _collect_instances_from_response(payload):
    if type(payload) != 'dict':
        return []
    for key in ['instances', 'data', 'results', 'items']:
        value = payload.get(key)
        if type(value) == 'list':
            return value
    if type(payload.get('instance')) == 'dict':
        return [payload.get('instance')]
    return []

def _query_by_hostname(config, token, class_name, dataset_id, hostname, http_options):
    if hostname == '':
        return []
    response = http_get(
        url=_helix_endpoint(config, 'cmdb_query_path', class_name, dataset_id),
        headers=_helix_headers(token),
        params={'hostname': hostname},
        **http_options
    )
    if not response:
        return []
    if response.status_code != 200:
        _log('Helix hostname lookup failed status={} host={}'.format(response.status_code, hostname))
        return []
    return _collect_instances_from_response(_safe_json_decode(response.body))

def _query_by_serial(config, token, class_name, dataset_id, serial, http_options):
    if serial == '':
        return []
    response = http_get(
        url=_helix_endpoint(config, 'cmdb_query_path', class_name, dataset_id),
        headers=_helix_headers(token),
        params={'serialNumber': serial},
        **http_options
    )
    if not response:
        return []
    if response.status_code != 200:
        _log('Helix serial lookup failed status={} serial={}'.format(response.status_code, serial))
        return []
    return _collect_instances_from_response(_safe_json_decode(response.body))

def _instance_id(instance):
    if type(instance) != 'dict':
        return ''
    for key in ['instanceId', 'id', 'recId']:
        value = _text(instance.get(key)).strip()
        if value != '':
            return value
    attributes = instance.get('attributes')
    if type(attributes) == 'dict':
        for key in ['InstanceId', 'ReconciliationIdentity', 'RequestId']:
            value = _text(attributes.get(key)).strip()
            if value != '':
                return value
    return ''

def _request_helix_access_token(config, client_id, client_secret, http_options):
    auth_path = config.get('auth_login_path', '')
    if auth_path == '' or auth_path == '/api/jwt/login':
        auth_path = '/api/rx/authentication/oauth/token'
    token_url = _join_url(config.get('helix_api_base', ''), auth_path)
    response = http_post(
        url=token_url,
        headers={
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Authorization': basic(client_id, client_secret),
        },
        body=bytes(url_encode({
            'grant_type': 'client_credentials',
        })),
        **http_options
    )
    if not response:
        _log('Helix token request returned no response')
        return ''
    if response.status_code < 200 or response.status_code >= 300:
        _log('Helix token request failed status={} body={}'.format(response.status_code, _trim(response.body, config.get('max_log_body', 800))))
        return ''

    payload = _safe_json_decode(response.body)
    token = ''
    if type(payload) == 'dict':
        for key in ['access_token', 'token', 'jwt', 'id_token']:
            token = _text(payload.get(key)).strip()
            if token != '':
                break
    elif type(payload) == 'string':
        token = payload.strip()
    if token == '':
        token = _text(response.body).strip()
    if token == '':
        _log('Helix token response missing access token')
    return token

def _get_runzero_assets(config, access_token, http_options):
    response = http_get(
        url=_join_url(config.get('runzero_console_url', ''), RUNZERO_EXPORT_PATH),
        headers={
            'Authorization': 'Bearer {}'.format(access_token),
            'Accept': 'application/json',
        },
        params={'search': config.get('runzero_search', '')} if _text(config.get('runzero_search')).strip() != '' else {},
        **http_options
    )
    if not response:
        _log('runZero export request returned no response')
        return []
    if response.status_code != 200:
        _log('runZero export failed status={} body={}'.format(response.status_code, _trim(response.body, config.get('max_log_body', 800))))
        return []

    payload = _safe_json_decode(response.body)
    if type(payload) != 'list':
        _log('runZero export payload was not a list; got type={}'.format(type(payload)))
        return []

    _log('Fetched {} assets from runZero export'.format(len(payload)))
    return payload

def _update_instance(config, token, class_name, dataset_id, instance_id, payload, http_options):
    headers = _helix_headers(token)
    headers['X-HTTP-Method-Override'] = 'PATCH'
    response = http_post(
        url=_helix_endpoint(config, 'cmdb_update_path', class_name, dataset_id, instance_id),
        headers=headers,
        body=bytes(json_encode(payload)),
        **http_options
    )
    if not response:
        return False
    if response.status_code < 200 or response.status_code >= 300:
        _log('Helix update failed status={} id={} body={}'.format(response.status_code, instance_id, _trim(response.body, config.get('max_log_body', 800))))
        return False
    return True

def _create_instance(config, token, class_name, dataset_id, payload, http_options):
    response = http_post(
        url=_helix_endpoint(config, 'cmdb_create_path', class_name, dataset_id),
        headers=_helix_headers(token),
        body=bytes(json_encode(payload)),
        **http_options
    )
    if not response:
        return False
    if response.status_code < 200 or response.status_code >= 300:
        _log('Helix create failed status={} body={}'.format(response.status_code, _trim(response.body, config.get('max_log_body', 800))))
        return False
    return True

def _post_ast_attributes(config, token, dataset_id, class_name, instance_id, source_asset_id, http_options):
    response = http_post(
        url=_join_url(config.get('helix_api_base', ''), config.get('ast_attributes_path', '/api/arsys/v1/entry/AST:Attributes')),
        headers=_helix_headers(token),
        body=bytes(json_encode({
            'values': {
                'DatasetId': dataset_id,
                'ClassName': _class_path(class_name),
                'InstanceId': instance_id,
                'SourceAssetId': source_asset_id,
            },
        })),
        **http_options
    )
    if not response:
        _log('AST attributes post returned no response for instance={}'.format(instance_id))
        return False
    if response.status_code < 200 or response.status_code >= 300:
        _log('AST attributes post failed status={} id={} body={}'.format(response.status_code, instance_id, _trim(response.body, config.get('max_log_body', 800))))
        return False
    return True

def _upsert_asset(config, token, class_name, dataset_id, asset, helix_http_options):
    payload = _map_asset_to_helix_payload(asset, class_name, dataset_id, config)
    names = _candidate_hostnames(asset)
    serials = _candidate_serials(asset)

    hostname_matches = []
    serial_matches = []
    if len(names) > 0:
        hostname_matches = _query_by_hostname(config, token, class_name, dataset_id, names[0], helix_http_options)
    if len(hostname_matches) == 0 and len(serials) > 0:
        serial_matches = _query_by_serial(config, token, class_name, dataset_id, serials[0], helix_http_options)

    matches = hostname_matches
    lookup_source = 'hostname'
    if len(matches) == 0 and len(serial_matches) > 0:
        matches = serial_matches
        lookup_source = 'serial'

    if len(matches) > 1:
        _log('Conflict: multiple matches found for asset id={} lookup={} class={}'.format(_first_non_empty(asset, ['id', 'asset_id', 'uuid']), lookup_source, class_name))
        return 'failed'

    if len(matches) == 1:
        instance_id = _instance_id(matches[0])
        if instance_id == '':
            _log('Failed to resolve instance ID for update path class={}'.format(class_name))
            return 'failed'

        if not _update_instance(config, token, class_name, dataset_id, instance_id, payload, helix_http_options):
            return 'failed'

        if config.get('post_ast_attributes'):
            _post_ast_attributes(config, token, dataset_id, class_name, instance_id, _first_non_empty(asset, ['id', 'asset_id', 'uuid']), helix_http_options)
        return 'updated'

    if not _create_instance(config, token, class_name, dataset_id, payload, helix_http_options):
        return 'failed'

    if config.get('post_ast_attributes'):
        instance_id = ''
        if len(names) > 0:
            created_matches = _query_by_hostname(config, token, class_name, dataset_id, names[0], helix_http_options)
            if len(created_matches) == 1:
                instance_id = _instance_id(created_matches[0])
        if instance_id == '' and len(serials) > 0:
            created_matches = _query_by_serial(config, token, class_name, dataset_id, serials[0], helix_http_options)
            if len(created_matches) == 1:
                instance_id = _instance_id(created_matches[0])
        if instance_id != '':
            _post_ast_attributes(config, token, dataset_id, class_name, instance_id, _first_non_empty(asset, ['id', 'asset_id', 'uuid']), helix_http_options)

    return 'created'

def build_config(kwargs):
    return {
        'runzero_console_url': get_string(kwargs, 'runzero_console_url'),
        'runzero_search': get_string(kwargs, 'runzero_search'),
        'runzero_timeout': get_int(kwargs, 'runzero_timeout', default=600),
        'helix_api_base': get_string(kwargs, 'helix_api_base'),
        'helix_dataset_id': get_string(kwargs, 'helix_dataset_id'),
        'class_names': DEFAULT_CLASS_NAMES,
        'auth_login_path': get_string(kwargs, 'auth_login_path'),
        'cmdb_query_path': get_string(kwargs, 'cmdb_query_path'),
        'cmdb_create_path': get_string(kwargs, 'cmdb_create_path'),
        'cmdb_update_path': get_string(kwargs, 'cmdb_update_path'),
        'ast_attributes_path': get_string(kwargs, 'ast_attributes_path'),
        'post_ast_attributes': get_bool(kwargs, 'post_ast_attributes', default=False),
        'helix_timeout': get_int(kwargs, 'helix_timeout', default=120),
        'max_log_body': get_int(kwargs, 'max_log_body', default=800),
        'system_environment': get_string(kwargs, 'system_environment'),
        'ip_category': get_string(kwargs, 'ip_category'),
        'ip_type': get_string(kwargs, 'ip_type'),
        'ip_item': get_string(kwargs, 'ip_item'),
        'os_category': get_string(kwargs, 'os_category'),
        'os_type': get_string(kwargs, 'os_type'),
        'os_item': get_string(kwargs, 'os_item'),
        'lan_category': get_string(kwargs, 'lan_category'),
        'lan_type': get_string(kwargs, 'lan_type'),
        'lan_item': get_string(kwargs, 'lan_item'),
        'hardware_category': get_string(kwargs, 'hardware_category'),
        'hardware_type': get_string(kwargs, 'hardware_type'),
        'hardware_item': get_string(kwargs, 'hardware_item'),
    }

def main(*args, **kwargs):
    require(
        kwargs,
        'runzero_export_token',
        'helix_client_id',
        'helix_client_secret',
        'runzero_console_url',
        'helix_api_base',
        'helix_dataset_id',
    )

    config = build_config(kwargs)
    rz_http_options = get_http_options(kwargs, 'rz_http_', 'rz_tls_')
    helix_http_options = get_http_options(kwargs, 'helix_http_', 'helix_tls_')

    _log('Starting Helix outbound sync classes={} dataset={}'.format(len(config.get('class_names', [])), config.get('helix_dataset_id', '')))

    assets = _get_runzero_assets(config, get_string(kwargs, 'runzero_export_token'), rz_http_options)
    if len(assets) == 0:
        _log('No assets to process')
        return None

    token = _request_helix_access_token(
        config,
        get_string(kwargs, 'helix_client_id'),
        get_string(kwargs, 'helix_client_secret'),
        helix_http_options,
    )
    if token == '':
        _log('Cannot continue without Helix access token')
        return None

    counters = {
        'processed_assets': 0,
        'processed_records': 0,
        'created': 0,
        'updated': 0,
        'failed': 0,
    }

    dataset_id = config.get('helix_dataset_id', '')
    for asset in assets:
        counters['processed_assets'] = counters['processed_assets'] + 1
        target_classes = _routed_classes(asset, config.get('class_names', []))

        for class_name in target_classes:
            counters['processed_records'] = counters['processed_records'] + 1
            result = _upsert_asset(config, token, class_name, dataset_id, asset, helix_http_options)
            if result == 'created':
                counters['created'] = counters['created'] + 1
            elif result == 'updated':
                counters['updated'] = counters['updated'] + 1
            else:
                counters['failed'] = counters['failed'] + 1

    _log('Completed Helix outbound sync assets={} records={} created={} updated={} failed={}'.format(
        counters['processed_assets'],
        counters['processed_records'],
        counters['created'],
        counters['updated'],
        counters['failed'],
    ))
    return None
