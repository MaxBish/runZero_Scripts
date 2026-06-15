load('json', json_encode='encode', json_decode='decode')
load('http', http_get='get', http_post='post')

# runZero defaults
RUNZERO_CONSOLE_URL_DEFAULT = 'https://console.runzero.com'
RUNZERO_EXPORT_PATH = '/api/v1.0/export/org/assets.json'
RUNZERO_TIMEOUT = 600

# Helix defaults (replace these for your tenant)
HELIX_API_BASE_DEFAULT = 'https://<UPDATE_ME_HELIX_HOST>'
HELIX_OAUTH_TOKEN_PATH_DEFAULT = '/api/oauth2/token'
HELIX_CMDB_QUERY_PATH_DEFAULT = '/api/cmdb/v1/instance/{className}'
HELIX_CMDB_CREATE_PATH_DEFAULT = '/api/cmdb/v1/instance/{className}'
HELIX_CMDB_UPDATE_PATH_DEFAULT = '/api/cmdb/v1/instance/{className}/{instanceId}'
HELIX_TIMEOUT = 120

# Runtime toggles
DRY_RUN_DEFAULT = True
MAX_LOG_BODY = 800
ENABLE_CLASS_ROUTING_DEFAULT = True

# Global mapping fields applied to every routed class payload.
GLOBAL_MAPPING_FIELDS = {
    'id': 'SourceAssetId',
    'os': 'OperatingSystem',
    'osVersion': 'OSVersion',
    'manufacturer': 'ManufacturerName',
    'model': 'Model',
}

# Extracted from runzero_helix_mapping.xlsx sheet tabs.
CLASS_FIELD_MAPPINGS = {
    'BMC_ComputerSystem': {
        'Name': ['fqdn', 'fqdnHostname', 'hostname', 'name'],
        'Short Description': ['hostname', 'name'],
        'SerialNumber': ['serialNumber', 'serial', 'serial_number'],
        'Supported': '__supported__',
        'Status': '__status__',
        'Company': '__company__',
        'PrimaryCapability': '__computer_primary_capability__',
    },
    'BMC_IPEndpoint': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'Supported': '__supported__',
        'Status': '__status__',
        'Company': '__company__',
        'Description': '__additional_information__',
        'Category': '__ip_category__',
    },
    'BMC_OperatingSystem': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'Supported': '__supported__',
        'Status': '__status__',
        'Company': '__company__',
        'Description': '__additional_information__',
        'Category': '__os_category__',
    },
    'BMC_LANEndpoint': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'Supported': '__supported__',
        'Status': '__status__',
        'Company': '__company__',
        'Description': '__additional_information__',
        'Category': '__lan_category__',
    },
    'BMC_HardwareSystemComponent': {
        'Name': '__ci_name__',
        'Short Description': '__ci_description__',
        'Supported': '__supported__',
        'SerialNumber': ['serialNumber', 'serial', 'serial_number'],
        'Status': '__status__',
        'Company': '__company__',
        'Description': '__additional_information__',
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


def _log(message):
    print('[HELIX-CMDB-OUTBOUND] {}'.format(str(message)))


def _trim(text, max_len):
    value = str(text)
    if len(value) <= max_len:
        return value
    return value[:max_len]


def _text(value):
    if value == None:
        return ''
    if type(value) == 'dict' or type(value) == 'list':
        return json_encode(value)
    return str(value)


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


def _lower(value):
    return _text(value).strip().lower()


def _bool_from_kwargs(kwargs, key, default_value):
    value = _lower(kwargs.get(key))
    if value in ['1', 'true', 'yes', 'on']:
        return True
    if value in ['0', 'false', 'no', 'off']:
        return False
    return default_value


def _normalize_url(base_url):
    text = _text(base_url).strip()
    if text == '':
        return ''
    text = text.rstrip('/')
    if text.startswith('https://') or text.startswith('http://'):
        return text
    return 'https://' + text


def _join_url(base_url, path):
    return base_url.rstrip('/') + '/' + path.lstrip('/')


def _safe_json_decode(body):
    if body == None:
        return None
    payload_text = _text(body).strip()
    if payload_text == '':
        return None
    return json_decode(payload_text)


def _build_runzero_headers(export_token):
    return {
        'Authorization': 'Bearer {}'.format(export_token),
        'Accept': 'application/json',
    }


def _contains(value, token):
    return token in _lower(value)


def _extract_runzero_export_token(kwargs):
    # Prefer explicit runZero token key, fallback to access_secret for compatibility.
    token = _text(kwargs.get('runzero_export_token')).strip()
    if token != '':
        return token

    token = _text(kwargs.get('access_secret')).strip()
    return token


def _get_runzero_assets(kwargs):
    export_token = _extract_runzero_export_token(kwargs)
    if export_token == '':
        _log('Missing runZero export token. Provide kwargs runzero_export_token or access_secret.')
        return []

    console_url = _normalize_url(kwargs.get('runzero_console_url'))
    if console_url == '':
        console_url = RUNZERO_CONSOLE_URL_DEFAULT

    search = _text(kwargs.get('runzero_search')).strip()
    url = _join_url(console_url, RUNZERO_EXPORT_PATH)
    params = {}
    if search != '':
        params['search'] = search

    response = http_get(url=url, headers=_build_runzero_headers(export_token), params=params, timeout=RUNZERO_TIMEOUT)
    if not response:
        _log('runZero export request returned no response')
        return []

    if response.status_code != 200:
        _log('runZero export failed status={} body={}'.format(response.status_code, _trim(_text(response.body), MAX_LOG_BODY)))
        return []

    payload = _safe_json_decode(response.body)
    if type(payload) != 'list':
        _log('runZero export payload was not a list; got type={}'.format(type(payload)))
        return []

    _log('Fetched {} assets from runZero export'.format(len(payload)))
    return payload


def _helix_oauth_token_url(kwargs, api_base):
    path = _text(kwargs.get('helix_oauth_token_path')).strip()
    if path == '':
        path = HELIX_OAUTH_TOKEN_PATH_DEFAULT
    return _join_url(api_base, path)


def _request_helix_access_token(kwargs):
    api_base = _normalize_url(kwargs.get('helix_api_base'))
    if api_base == '':
        api_base = HELIX_API_BASE_DEFAULT

    client_id = _text(kwargs.get('helix_client_id')).strip()
    client_secret = _text(kwargs.get('helix_client_secret')).strip()

    if client_id == '' or client_secret == '':
        _log('Missing Helix OAuth credentials: helix_client_id and helix_client_secret are required')
        return ''

    token_url = _helix_oauth_token_url(kwargs, api_base)

    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
    }
    body = bytes('grant_type=client_credentials&client_id={}&client_secret={}'.format(client_id, client_secret))

    response = http_post(url=token_url, headers=headers, body=body, timeout=HELIX_TIMEOUT)
    if not response:
        _log('Helix token request returned no response')
        return ''

    if response.status_code != 200:
        _log('Helix token request failed status={} body={}'.format(response.status_code, _trim(_text(response.body), MAX_LOG_BODY)))
        return ''

    payload = _safe_json_decode(response.body)
    token = ''
    if type(payload) == 'dict':
        token = _text(payload.get('access_token')).strip()

    if token == '':
        _log('Helix token response missing access_token')

    return token


def _helix_headers(token):
    return {
        'Authorization': 'Bearer {}'.format(token),
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    }


def _render_path(template, class_name, instance_id):
    path = template
    path = path.replace('{className}', class_name)
    path = path.replace('{instanceId}', instance_id)
    return path


def _helix_endpoint(kwargs, path_default, class_name, instance_id=''):
    api_base = _normalize_url(kwargs.get('helix_api_base'))
    if api_base == '':
        api_base = HELIX_API_BASE_DEFAULT

    path = _text(kwargs.get(path_default)).strip()
    if path == '':
        if path_default == 'helix_cmdb_query_path':
            path = HELIX_CMDB_QUERY_PATH_DEFAULT
        elif path_default == 'helix_cmdb_create_path':
            path = HELIX_CMDB_CREATE_PATH_DEFAULT
        elif path_default == 'helix_cmdb_update_path':
            path = HELIX_CMDB_UPDATE_PATH_DEFAULT

    path = _render_path(path, class_name, instance_id)
    return _join_url(api_base, path)


def _candidate_hostnames(asset):
    names = []

    # Export may carry names in multiple shapes.
    primary = _first_non_empty(asset, ['hostname', 'name', 'fqdn'])
    if primary != '':
        names.append(primary)

    for key in ['hostnames', 'names']:
        values = _as_list(asset.get(key))
        for value in values:
            text = _text(value).strip()
            if text != '':
                names.append(text)

    # de-duplicate while preserving order
    deduped = []
    seen = {}
    for name in names:
        lowered = name.lower()
        if lowered in seen:
            continue
        seen[lowered] = True
        deduped.append(name)

    return deduped


def _candidate_serials(asset):
    serials = []

    primary = _first_non_empty(asset, ['serial', 'serialNumber'])
    if primary != '':
        serials.append(primary)

    for key in ['serial_numbers', 'serialNumbers']:
        values = _as_list(asset.get(key))
        for value in values:
            text = _text(value).strip()
            if text != '':
                serials.append(text)

    deduped = []
    seen = {}
    for serial in serials:
        if serial in seen:
            continue
        seen[serial] = True
        deduped.append(serial)

    return deduped


def _candidate_ips(asset):
    ips = []
    for key in ['addresses', 'ipAddresses', 'ip_addresses', 'ips']:
        for item in _as_list(asset.get(key)):
            text = _text(item).strip()
            if text != '':
                ips.append(text)

    primary = _first_non_empty(asset, ['ip', 'ipAddress', 'address'])
    if primary != '':
        ips.append(primary)

    deduped = []
    seen = {}
    for ip in ips:
        if ip in seen:
            continue
        seen[ip] = True
        deduped.append(ip)
    return deduped


def _candidate_macs(asset):
    macs = []
    for key in ['macs', 'macAddresses', 'mac_addresses']:
        for item in _as_list(asset.get(key)):
            text = _text(item).strip()
            if text != '':
                macs.append(text)

    primary = _first_non_empty(asset, ['mac', 'macAddress', 'mac_address'])
    if primary != '':
        macs.append(primary)

    deduped = []
    seen = {}
    for mac in macs:
        lowered = mac.lower()
        if lowered in seen:
            continue
        seen[lowered] = True
        deduped.append(mac)
    return deduped


def _status_from_asset(asset):
    # Priority: explicit override, lifecycle translation, then default.
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

    # If source already looks like a valid BMC status, keep it.
    if source in ['Reserved', 'Being Assembled', 'Deployed', 'Down', 'End of Life', 'Ordered']:
        return source

    return 'Deployed'


def _ci_name(asset):
    names = _candidate_hostnames(asset)
    if len(names) > 0:
        return names[0]

    ips = _candidate_ips(asset)
    if len(ips) > 0:
        return ips[0]

    serials = _candidate_serials(asset)
    if len(serials) > 0:
        return serials[0]

    return _first_non_empty(asset, ['id', 'asset_id', 'uuid'])


def _ci_description(asset):
    return _first_non_empty(asset, ['hostname', 'name', 'description', 'os'])


def _additional_information(asset):
    details = []
    os_name = _first_non_empty(asset, ['os'])
    os_ver = _first_non_empty(asset, ['osVersion', 'os_version'])
    if os_name != '':
        details.append('os={}'.format(os_name))
    if os_ver != '':
        details.append('osVersion={}'.format(os_ver))

    manufacturer = _first_non_empty(asset, ['manufacturer'])
    model = _first_non_empty(asset, ['model'])
    if manufacturer != '':
        details.append('manufacturer={}'.format(manufacturer))
    if model != '':
        details.append('model={}'.format(model))

    if len(details) == 0:
        return _first_non_empty(asset, ['description'])

    return ', '.join(details)


def _resolve_mapping_token(asset, kwargs, token):
    if token == '__supported__':
        return _text(kwargs.get('helix_supported_default')).strip() or 'Yes'
    if token == '__status__':
        return _status_from_asset(asset)
    if token == '__company__':
        return _text(kwargs.get('helix_company')).strip()
    if token == '__computer_primary_capability__':
        return _text(kwargs.get('helix_primary_capability')).strip() or 'Server'
    if token == '__ci_name__':
        return _ci_name(asset)
    if token == '__ci_description__':
        return _ci_description(asset)
    if token == '__additional_information__':
        return _additional_information(asset)
    if token == '__ip_category__':
        return _text(kwargs.get('helix_ip_category')).strip() or 'Network'
    if token == '__os_category__':
        return _text(kwargs.get('helix_os_category')).strip() or 'Software'
    if token == '__lan_category__':
        return _text(kwargs.get('helix_lan_category')).strip() or 'Network'
    return ''


def _resolve_field_spec(asset, kwargs, spec):
    if type(spec) == 'string':
        if spec.startswith('__') and spec.endswith('__'):
            return _resolve_mapping_token(asset, kwargs, spec)
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


def _routed_classes(asset, explicit_class, class_routing_enabled):
    if explicit_class != '' and not class_routing_enabled:
        return [explicit_class]

    classes = []
    if explicit_class != '' and class_routing_enabled:
        if _should_route_to_class(asset, explicit_class):
            classes.append(explicit_class)
        return classes

    for class_name, _ in CLASS_FIELD_MAPPINGS.items():
        if _should_route_to_class(asset, class_name):
            classes.append(class_name)

    if len(classes) == 0:
        classes.append('BMC_ComputerSystem')

    return classes


def _map_asset_to_helix_payload(asset, class_name, dataset_id, kwargs):
    payload = {
        'className': class_name,
        'datasetId': dataset_id,
        'attributes': {},
    }

    # Apply global field mapping first.
    attrs = payload['attributes']
    for source_key, target_key in GLOBAL_MAPPING_FIELDS.items():
        value = asset.get(source_key)
        if value == None:
            continue

        text = _text(value).strip()
        if text == '':
            continue

        attrs[target_key] = text

    # Apply class-specific mappings from spreadsheet tabs.
    class_map = CLASS_FIELD_MAPPINGS.get(class_name)
    if type(class_map) == 'dict':
        for target_key, field_spec in class_map.items():
            value = _resolve_field_spec(asset, kwargs, field_spec)
            value_text = _text(value).strip()
            if value_text == '':
                continue
            attrs[target_key] = value_text

    # Add common identity hints to help with troubleshooting.
    names = _candidate_hostnames(asset)
    serials = _candidate_serials(asset)
    if len(names) > 0 and 'Name' not in attrs:
        attrs['Name'] = names[0]
    if len(serials) > 0 and 'SerialNumber' not in attrs:
        attrs['SerialNumber'] = serials[0]

    attrs['RunZeroAssetId'] = _first_non_empty(asset, ['id', 'asset_id', 'uuid'])

    return payload


def _collect_instances_from_response(payload):
    if type(payload) != 'dict':
        return []

    # Handle common response containers used by CMDB APIs.
    for key in ['instances', 'data', 'results', 'items']:
        value = payload.get(key)
        if type(value) == 'list':
            return value

    if type(payload.get('instance')) == 'dict':
        return [payload.get('instance')]

    return []


def _query_by_hostname(kwargs, token, class_name, dataset_id, hostname):
    if hostname == '':
        return []

    url = _helix_endpoint(kwargs, 'helix_cmdb_query_path', class_name)
    params = {
        'datasetId': dataset_id,
        'hostname': hostname,
    }

    response = http_get(url=url, headers=_helix_headers(token), params=params, timeout=HELIX_TIMEOUT)
    if not response:
        return []
    if response.status_code != 200:
        _log('Helix hostname lookup failed status={} host={}'.format(response.status_code, hostname))
        return []

    payload = _safe_json_decode(response.body)
    return _collect_instances_from_response(payload)


def _query_by_serial(kwargs, token, class_name, dataset_id, serial):
    if serial == '':
        return []

    url = _helix_endpoint(kwargs, 'helix_cmdb_query_path', class_name)
    params = {
        'datasetId': dataset_id,
        'serialNumber': serial,
    }

    response = http_get(url=url, headers=_helix_headers(token), params=params, timeout=HELIX_TIMEOUT)
    if not response:
        return []
    if response.status_code != 200:
        _log('Helix serial lookup failed status={} serial={}'.format(response.status_code, serial))
        return []

    payload = _safe_json_decode(response.body)
    return _collect_instances_from_response(payload)


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


def _update_instance(kwargs, token, class_name, instance_id, payload):
    url = _helix_endpoint(kwargs, 'helix_cmdb_update_path', class_name, instance_id)
    response = http_post(url=url, headers=_helix_headers(token), body=bytes(json_encode(payload)), timeout=HELIX_TIMEOUT)
    if not response:
        return False
    if response.status_code < 200 or response.status_code >= 300:
        _log('Helix update failed status={} id={} body={}'.format(response.status_code, instance_id, _trim(_text(response.body), MAX_LOG_BODY)))
        return False
    return True


def _create_instance(kwargs, token, class_name, payload):
    url = _helix_endpoint(kwargs, 'helix_cmdb_create_path', class_name)
    response = http_post(url=url, headers=_helix_headers(token), body=bytes(json_encode(payload)), timeout=HELIX_TIMEOUT)
    if not response:
        return False
    if response.status_code < 200 or response.status_code >= 300:
        _log('Helix create failed status={} body={}'.format(response.status_code, _trim(_text(response.body), MAX_LOG_BODY)))
        return False
    return True


def _upsert_asset(kwargs, token, class_name, dataset_id, asset, dry_run):
    payload = _map_asset_to_helix_payload(asset, class_name, dataset_id, kwargs)
    names = _candidate_hostnames(asset)
    serials = _candidate_serials(asset)

    hostname_matches = []
    serial_matches = []

    if len(names) > 0:
        hostname_matches = _query_by_hostname(kwargs, token, class_name, dataset_id, names[0])

    if len(hostname_matches) == 0 and len(serials) > 0:
        serial_matches = _query_by_serial(kwargs, token, class_name, dataset_id, serials[0])

    matches = hostname_matches
    lookup_source = 'hostname'
    if len(matches) == 0 and len(serial_matches) > 0:
        matches = serial_matches
        lookup_source = 'serial'

    if len(matches) > 1:
        _log('Conflict: multiple matches found for asset id={} lookup={}'.format(_first_non_empty(asset, ['id', 'asset_id', 'uuid']), lookup_source))
        return 'failed'

    if len(matches) == 1:
        instance_id = _instance_id(matches[0])
        if instance_id == '':
            _log('Failed to resolve instance ID for update path')
            return 'failed'

        if dry_run:
            _log('DRY-RUN update id={} lookup={} payload={}'.format(instance_id, lookup_source, _trim(json_encode(payload), MAX_LOG_BODY)))
            return 'updated'

        ok = _update_instance(kwargs, token, class_name, instance_id, payload)
        if ok:
            return 'updated'
        return 'failed'

    # Explicit net-new create path when no hostname/serial match was found.
    if dry_run:
        _log('DRY-RUN create net-new asset id={} payload={}'.format(_first_non_empty(asset, ['id', 'asset_id', 'uuid']), _trim(json_encode(payload), MAX_LOG_BODY)))
        return 'created'

    ok = _create_instance(kwargs, token, class_name, payload)
    if ok:
        return 'created'
    return 'failed'


def main(*args, **kwargs):
    class_name = _text(kwargs.get('helix_class_name')).strip()
    if class_name == '<UPDATE_ME_CLASS_NAME>':
        class_name = ''

    dataset_id = _text(kwargs.get('helix_dataset_id')).strip()
    if dataset_id == '':
        dataset_id = '<UPDATE_ME_DATASET_ID>'

    dry_run = _bool_from_kwargs(kwargs, 'dry_run', DRY_RUN_DEFAULT)
    class_routing_enabled = _bool_from_kwargs(kwargs, 'helix_class_routing', ENABLE_CLASS_ROUTING_DEFAULT)

    _log('Starting Helix outbound sync class={} dataset={} dry_run={} class_routing={}'.format(class_name or 'AUTO', dataset_id, dry_run, class_routing_enabled))

    assets = _get_runzero_assets(kwargs)
    if len(assets) == 0:
        _log('No assets to process')
        return None

    token = ''
    if not dry_run:
        token = _request_helix_access_token(kwargs)
        if token == '':
            _log('Cannot continue without Helix access token in live mode')
            return None

    counters = {
        'processed_assets': 0,
        'processed_records': 0,
        'created': 0,
        'updated': 0,
        'failed': 0,
    }

    for asset in assets:
        counters['processed_assets'] = counters['processed_assets'] + 1
        target_classes = _routed_classes(asset, class_name, class_routing_enabled)

        # In dry-run mode we still run lookup/update/create flow shape using placeholder token value.
        active_token = token
        if dry_run and active_token == '':
            active_token = 'DRY_RUN_TOKEN'

        for target_class in target_classes:
            counters['processed_records'] = counters['processed_records'] + 1
            result = _upsert_asset(kwargs, active_token, target_class, dataset_id, asset, dry_run)
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

    # Outbound scripts typically return None.
    return None
