load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_get='get')
load('time', 'parse_time')

DEFAULT_SOURCE_CONSOLE = 'https://console.runzero.com'
DEFAULT_TIMEOUT = 600


def _log(message):
    print('[RUNZERO-CONSOLE-SYNC] ' + str(message))


def _normalize_console_url(value):
    if value == None:
        return DEFAULT_SOURCE_CONSOLE

    text = str(value).strip()
    if text == '':
        return DEFAULT_SOURCE_CONSOLE

    text = text.rstrip('/')
    if text.startswith('http://') or text.startswith('https://'):
        return text

    return 'https://' + text


def _text(value):
    if value == None:
        return ''

    value_type = type(value)
    if value_type == 'dict' or value_type == 'list':
        return json_encode(value)

    return str(value)


def _truncate(text, limit):
    if text == None:
        return ''
    value = str(text)
    if len(value) <= limit:
        return value
    return value[:limit]


def _first_non_empty(record, keys):
    if type(record) != 'dict':
        return ''

    for key in keys:
        if key not in record:
            continue
        value = record.get(key)
        text = _text(value).strip()
        if text != '':
            return text

    return ''


def _first_nested_non_empty(record, outer_key, inner_keys):
    if type(record) != 'dict':
        return ''

    nested = record.get(outer_key)
    if type(nested) != 'dict':
        return ''

    for key in inner_keys:
        if key not in nested:
            continue
        value = nested.get(key)
        text = _text(value).strip()
        if text != '':
            return text

    return ''


def _string_list(value):
    if value == None:
        return []

    value_type = type(value)
    raw_items = []
    if value_type == 'list':
        raw_items = value
    elif value_type == 'dict':
        raw_items = [value]
    else:
        text = str(value).strip()
        if text == '':
            return []
        if ',' in text:
            raw_items = text.split(',')
        else:
            raw_items = [text]

    items = []
    seen = {}
    for item in raw_items:
        text = _text(item).strip()
        if text == '':
            continue
        if text not in seen:
            seen[text] = True
            items.append(text)

    return items


def _first_list(record, keys):
    if type(record) != 'dict':
        return []

    for key in keys:
        if key not in record:
            continue
        values = _string_list(record.get(key))
        if len(values) > 0:
            return values

    return []


def _safe_fragment(value, fallback):
    text = str(value).strip().lower()
    if text == '':
        text = fallback

    replacements = [
        (' ', '-'),
        ('_', '-'),
        ('/', '-'),
        (':', '-'),
        ('\\', '-'),
        ('.', '-'),
        ('@', '-'),
    ]

    for old, new in replacements:
        text = text.replace(old, new)

    while '--' in text:
        text = text.replace('--', '-')

    if text.endswith('-'):
        text = text[:-1]

    if text == '':
        text = fallback

    return text[:80]


def _normalize_ip(value):
    text = str(value).strip()
    if text == '':
        return ''

    if text.startswith('[') and ']' in text:
        text = text[1:text.find(']')]

    if '/' in text:
        text = text.split('/')[0]

    return text


def _parse_first_seen(value):
    text = _text(value).strip()
    if text == '':
        return None

    if 'T' not in text and ' ' not in text:
        return None

    parsed = parse_time(text)
    if parsed == None:
        return None

    return parsed


def _build_network_interfaces(record):
    addresses = _first_list(record, ['addresses', 'ip_addresses', 'ips', 'ipAddresses'])
    macs = _first_list(record, ['macs', 'mac_addresses', 'macAddresses'])

    ipv4s = []
    ipv6s = []
    for raw_ip in addresses[:99]:
        ip_text = _normalize_ip(raw_ip)
        if ip_text == '':
            continue
        ip_obj = ip_address(ip_text)
        if ip_obj == None:
            continue
        if ip_obj.version == 4:
            ipv4s.append(ip_obj)
        elif ip_obj.version == 6:
            ipv6s.append(ip_obj)

    interfaces = []
    if len(ipv4s) == 0 and len(ipv6s) == 0 and len(macs) == 0:
        return interfaces

    if len(macs) > 0:
        interfaces.append(NetworkInterface(macAddress=macs[0], ipv4Addresses=ipv4s, ipv6Addresses=ipv6s))
        for mac in macs[1:99]:
            interfaces.append(NetworkInterface(macAddress=mac))
    else:
        interfaces.append(NetworkInterface(ipv4Addresses=ipv4s, ipv6Addresses=ipv6s))

    return interfaces


def _custom_attrs(record, console_url):
    attrs = {}

    source_id = _first_non_empty(record, ['id', 'uuid', 'asset_id'])
    if source_id != '':
        attrs['runzero_source_asset_id'] = source_id

    attrs['runzero_source_console'] = console_url

    source_org = _first_non_empty(record, ['organization', 'org', 'tenant'])
    if source_org == '':
        source_org = _first_nested_non_empty(record, 'organization', ['name', 'id'])
    if source_org != '':
        attrs['runzero_source_organization'] = source_org

    source_site = _first_non_empty(record, ['site', 'site_name'])
    if source_site == '':
        source_site = _first_nested_non_empty(record, 'site', ['name', 'id'])
    if source_site != '':
        attrs['runzero_source_site'] = source_site

    first_seen = _first_non_empty(record, ['first_seen', 'firstSeen', 'firstSeenTS'])
    if first_seen != '':
        attrs['runzero_source_first_seen'] = first_seen

    last_seen = _first_non_empty(record, ['last_seen', 'lastSeen', 'last_seen_ts'])
    if last_seen != '':
        attrs['runzero_source_last_seen'] = last_seen

    detected_by = _first_non_empty(record, ['detected_by'])
    if detected_by != '':
        attrs['runzero_source_detected_by'] = detected_by

    alive = _first_non_empty(record, ['alive'])
    if alive != '':
        attrs['runzero_source_alive'] = alive

    risk_rank = _first_non_empty(record, ['risk_rank', 'modified_risk_rank'])
    if risk_rank != '':
        attrs['runzero_source_risk_rank'] = risk_rank

    comments = _first_non_empty(record, ['comments'])
    if comments != '':
        attrs['runzero_source_comments'] = comments

    domains = _first_list(record, ['domains'])
    if len(domains) > 0:
        attrs['runzero_source_domains'] = json_encode(domains)

    tags = _first_list(record, ['tags'])
    if len(tags) > 0:
        attrs['runzero_source_tags'] = json_encode(tags)

    snapshot = {
        'id': source_id,
        'names': _first_list(record, ['names', 'hostnames']),
        'addresses': _first_list(record, ['addresses', 'ip_addresses', 'ips', 'ipAddresses']),
        'macs': _first_list(record, ['macs', 'mac_addresses', 'macAddresses']),
        'os': _first_non_empty(record, ['os', 'operating_system', 'platform']),
        'os_version': _first_non_empty(record, ['osVersion', 'os_version', 'version']),
        'device_type': _first_non_empty(record, ['device_type', 'type', 'asset_type']),
        'manufacturer': _first_non_empty(record, ['manufacturer', 'vendor']),
        'model': _first_non_empty(record, ['model', 'hw']),
        'first_seen': first_seen,
        'last_seen': last_seen,
        'tags': tags,
        'domains': domains,
    }
    attrs['runzero_source_snapshot'] = _truncate(json_encode(snapshot), 1024)

    return attrs


def _build_asset_id(record):
    source_id = _first_non_empty(record, ['id', 'uuid', 'asset_id'])
    if source_id != '':
        return str(source_id)

    names = _first_list(record, ['names', 'hostnames'])
    addresses = _first_list(record, ['addresses', 'ip_addresses', 'ips', 'ipAddresses'])
    macs = _first_list(record, ['macs', 'mac_addresses', 'macAddresses'])

    name_fragment = 'asset'
    if len(names) > 0:
        name_fragment = _safe_fragment(names[0], 'asset')
    elif len(addresses) > 0:
        name_fragment = _safe_fragment(addresses[0], 'asset')
    elif len(macs) > 0:
        name_fragment = _safe_fragment(macs[0], 'asset')

    address_fragment = 'unknown'
    if len(addresses) > 0:
        address_fragment = _safe_fragment(addresses[0], 'unknown')

    mac_fragment = 'unknown'
    if len(macs) > 0:
        mac_fragment = _safe_fragment(macs[0], 'unknown')

    return 'runzero-sync-{}-{}-{}'.format(name_fragment, address_fragment, mac_fragment)


def _normalize_response(decoded):
    if decoded == None:
        return []

    decoded_type = type(decoded)
    if decoded_type == 'list':
        return decoded

    if decoded_type == 'dict':
        for key in ['assets', 'data', 'results', 'items', 'records']:
            value = decoded.get(key)
            if type(value) == 'list':
                return value

    return []


def _build_import_asset(record, console_url):
    asset_id = _build_asset_id(record)
    hostnames = _first_list(record, ['names', 'hostnames'])
    if len(hostnames) == 0:
        single_name = _first_non_empty(record, ['name', 'hostname', 'fqdn'])
        if single_name != '':
            hostnames = [single_name]

    tags = _first_list(record, ['tags'])
    os_name = _first_non_empty(record, ['os', 'operating_system', 'platform'])
    os_version = _first_non_empty(record, ['osVersion', 'os_version', 'version'])
    device_type = _first_non_empty(record, ['device_type', 'type', 'asset_type'])
    manufacturer = _first_non_empty(record, ['manufacturer', 'vendor'])
    model = _first_non_empty(record, ['model', 'hw'])
    domain = _first_non_empty(record, ['domain'])
    if domain == '':
        domains = _first_list(record, ['domains'])
        if len(domains) == 1:
            domain = domains[0]

    first_seen_value = _first_non_empty(record, ['first_seen', 'firstSeen', 'firstSeenTS'])
    first_seen_ts = _parse_first_seen(first_seen_value)
    interfaces = _build_network_interfaces(record)
    attrs = _custom_attrs(record, console_url)

    asset_params = {
        'id': asset_id,
        'customAttributes': attrs,
    }

    if len(hostnames) > 0:
        asset_params['hostnames'] = hostnames
    if len(tags) > 0:
        asset_params['tags'] = tags
    if domain != '':
        asset_params['domain'] = domain
    if os_name != '':
        asset_params['os'] = os_name
        asset_params['trust_os'] = True
    if os_version != '':
        asset_params['osVersion'] = os_version
        asset_params['trust_os_version'] = True
    if device_type != '':
        asset_params['deviceType'] = device_type
        asset_params['trust_device_type'] = True
    if manufacturer != '':
        asset_params['manufacturer'] = manufacturer
    if model != '':
        asset_params['model'] = model
    if first_seen_ts != None:
        asset_params['firstSeenTS'] = first_seen_ts
    if len(interfaces) > 0:
        asset_params['networkInterfaces'] = interfaces

    return ImportAsset(**asset_params)


def _fetch_export_assets(console_url, token):
    export_url = console_url + '/api/v1.0/export/org/assets.json'
    headers = {
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/json',
    }

    _log('Fetching exported assets from ' + export_url)
    response = http_get(export_url, headers=headers, timeout=DEFAULT_TIMEOUT)
    if response == None:
        _log('ERROR: no response from source console')
        return []

    if response.status_code != 200:
        _log('ERROR: export failed with status ' + str(response.status_code))
        if response.body != None:
            _log('ERROR: response body: ' + str(response.body))
        return []

    decoded = json_decode(response.body)
    assets = _normalize_response(decoded)
    _log('Fetched ' + str(len(assets)) + ' asset records')
    return assets


def main(*args, **kwargs):
    console_url = _normalize_console_url(kwargs.get('access_key'))
    export_token = kwargs.get('access_secret')

    if export_token == None or str(export_token).strip() == '':
        _log('ERROR: access_secret must contain the source export token')
        return []

    assets = _fetch_export_assets(console_url, str(export_token).strip())
    if len(assets) == 0:
        _log('No exported assets returned')
        return []

    import_assets = []
    for record in assets:
        if type(record) != 'dict':
            continue
        import_assets.append(_build_import_asset(record, console_url))

    _log('Built ' + str(len(import_assets)) + ' ImportAsset objects')
    return import_assets
