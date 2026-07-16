load('runzero.types', 'ImportAsset', 'NetworkInterface', 'Vulnerability')
load('json', json_encode='encode', json_decode='decode')
load('net', 'ip_address')
load('http', http_post='post')
load('uuid', 'new_uuid')

ONAPSIS_DEFAULT_BASE_URL = 'https://<your-onapsis-instance>'
ONAPSIS_TOKEN_PATH = '/api/v1/token'
ONAPSIS_GRAPHQL_PATH = '/graphql'

DEFAULT_PAGE_SIZE = 500
DEFAULT_MAX_PAGES = 100

ASSETS_QUERY = """
query GetAssets($first: Int, $after: Int) {
  assets(first: $first, after: $after) {
    id
    name
    host_name
    ip
    os
    status
  }
}
"""

VULNS_QUERY = """
query GetVulnerabilities($first: Int, $after: Int) {
  vulnerabilities(first: $first, after: $after) {
    state
    asset {
      id
      name
    }
    issue {
      okb_id
      name
      risk
      description
      solution
      cvss
      cve
    }
  }
}
"""


def safe_str(value):
    if value == None:
        return ''
    return str(value)


def is_int_text(txt):
    if txt == '':
        return False
    for ch in txt:
        if ch < '0' or ch > '9':
            return False
    return True


def is_float_text(txt):
    if txt == '':
        return False

    dot_seen = False
    digit_seen = False

    for ch in txt:
        if ch >= '0' and ch <= '9':
            digit_seen = True
            continue
        if ch == '.' and not dot_seen:
            dot_seen = True
            continue
        return False

    return digit_seen


def parse_int(value, default):
    if value == None:
        return default
    txt = str(value).strip()
    if not is_int_text(txt):
        return default
    return int(txt)


def clean_base_url(base_url):
    url = safe_str(base_url).strip()
    if url == '':
        url = ONAPSIS_DEFAULT_BASE_URL
    if url.endswith('/'):
        url = url[:-1]
    return url


def get_access_token(base_url, api_key):
    token_url = base_url + ONAPSIS_TOKEN_PATH
    headers = {
        'Accept': 'application/json',
        'Authorization': 'Basic {}'.format(api_key),
    }

    response = http_post(token_url, headers=headers)
    if not response:
        print('Onapsis: token request failed (no response).')
        return ''

    if response.status_code < 200 or response.status_code >= 300:
        print('Onapsis: token request failed status={} body={}'.format(response.status_code, safe_str(response.body)[:500]))
        return ''

    payload = json_decode(response.body)
    if type(payload) != 'dict':
        print('Onapsis: token response was not JSON object.')
        return ''

    token = safe_str(payload.get('access_token', ''))
    if token == '':
        print('Onapsis: token response missing access_token.')
        return ''

    return token


def graphql_request(base_url, token, query, variables):
    body = bytes(json_encode({'query': query, 'variables': variables}))
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer {}'.format(token),
    }

    response = http_post(base_url + ONAPSIS_GRAPHQL_PATH, headers=headers, body=body)
    if not response:
        return {'ok': False, 'error': 'no response'}

    if response.status_code < 200 or response.status_code >= 300:
        return {
            'ok': False,
            'error': 'status={} body={}'.format(response.status_code, safe_str(response.body)[:500]),
        }

    payload = json_decode(response.body)
    if type(payload) != 'dict':
        return {'ok': False, 'error': 'response not JSON object'}

    if type(payload.get('errors')) == 'list' and len(payload.get('errors')) > 0:
        return {
            'ok': False,
            'error': safe_str(payload.get('errors'))[:900],
        }

    data = payload.get('data', {})
    if type(data) != 'dict':
        data = {}

    return {'ok': True, 'data': data}


def paginate_graphql_list(base_url, token, query, root_field, page_size, max_pages):
    items = []
    offset = 0

    for page in range(max_pages):
        variables = {
            'first': page_size,
            'after': offset,
        }

        result = graphql_request(base_url, token, query, variables)
        if not result.get('ok', False):
            print('Onapsis: GraphQL query failed for {} at page {}: {}'.format(root_field, page, result.get('error', 'unknown error')))
            return None

        data = result.get('data', {})
        batch = data.get(root_field, [])
        if type(batch) != 'list':
            print('Onapsis: {} response was not a list.'.format(root_field))
            return None

        if len(batch) == 0:
            break

        for item in batch:
            items.append(item)

        if len(batch) < page_size:
            break

        offset = offset + len(batch)

    return items


def build_network_interface(ip_raw):
    ip_text = safe_str(ip_raw)
    if ip_text == '':
        return None

    has_dot = False
    has_colon = False
    for ch in ip_text:
        if ch == '.':
            has_dot = True
        if ch == ':':
            has_colon = True

    if not has_dot and not has_colon:
        return None

    addr = ip_address(ip_text)
    ip4s = []
    ip6s = []

    if addr.version == 4:
        ip4s.append(addr)
    elif addr.version == 6:
        ip6s.append(addr)

    return NetworkInterface(ipv4Addresses=ip4s, ipv6Addresses=ip6s)


def map_risk_to_rank(risk):
    txt = safe_str(risk).strip().lower()
    if txt in ('critical', 'very high', '4', '5'):
        return 4
    if txt in ('high', '3'):
        return 3
    if txt in ('medium', 'moderate', '2'):
        return 2
    if txt in ('low', '1'):
        return 1
    return 0


def map_risk_to_score(risk):
    txt = safe_str(risk).strip()
    if not is_float_text(txt):
        return 0.0
    return float(txt)


def build_vulnerability(vuln_row):
    issue = vuln_row.get('issue', {})
    if type(issue) != 'dict':
        issue = {}

    okb_id = safe_str(issue.get('okb_id', ''))
    vuln_id = okb_id
    if vuln_id == '':
        vuln_id = new_uuid()

    risk_text = issue.get('risk', '')
    rank = map_risk_to_rank(risk_text)

    score_value = issue.get('cvss', None)
    if score_value == None:
        score_value = risk_text

    score = map_risk_to_score(score_value)

    custom = {
        'state': safe_str(vuln_row.get('state', '')),
        'okb_id': okb_id,
    }

    return Vulnerability(
        id=vuln_id,
        name=safe_str(issue.get('name', vuln_id)),
        description=safe_str(issue.get('description', '')),
        solution=safe_str(issue.get('solution', '')),
        cve=safe_str(issue.get('cve', '')).upper(),
        severityRank=rank,
        severityScore=score,
        riskRank=rank,
        riskScore=score,
        customAttributes=custom,
    )


def add_asset_from_assets_query(asset_map, raw_asset):
    asset_id = safe_str(raw_asset.get('id', ''))
    if asset_id == '':
        return

    hostname = safe_str(raw_asset.get('name', raw_asset.get('host_name', '')))
    hostnames = []
    if hostname != '':
        hostnames.append(hostname)

    network_interfaces = []
    netif = build_network_interface(raw_asset.get('ip', ''))
    if netif != None:
        network_interfaces.append(netif)

    custom = {
        'source': 'onapsis',
        'status': safe_str(raw_asset.get('status', '')),
    }

    asset_map[asset_id] = ImportAsset(
        id='onapsis:{}'.format(asset_id),
        hostnames=hostnames,
        os=safe_str(raw_asset.get('os', '')),
        networkInterfaces=network_interfaces,
        vulnerabilities=[],
        customAttributes=custom,
    )


def ensure_asset_for_vuln(asset_map, asset_ref):
    if type(asset_ref) != 'dict':
        return ''

    asset_id = safe_str(asset_ref.get('id', ''))
    if asset_id == '':
        return ''

    if asset_id not in asset_map:
        hostname = safe_str(asset_ref.get('name', ''))
        hostnames = []
        if hostname != '':
            hostnames.append(hostname)

        asset_map[asset_id] = ImportAsset(
            id='onapsis:{}'.format(asset_id),
            hostnames=hostnames,
            vulnerabilities=[],
            customAttributes={'source': 'onapsis'},
        )

    return asset_id


def attach_vulnerabilities(asset_map, vuln_rows):
    for row in vuln_rows:
        if type(row) != 'dict':
            continue

        asset_id = ensure_asset_for_vuln(asset_map, row.get('asset', {}))
        if asset_id == '':
            continue

        asset = asset_map.get(asset_id)
        if asset == None:
            continue

        asset.vulnerabilities.append(build_vulnerability(row))


def main(*args, **kwargs):
    """Import Onapsis assets and vulnerabilities into runZero.

    access_key: optional Onapsis base URL (e.g., https://onapsis.example)
    access_secret: required API key used to mint a bearer token
    page_size: optional GraphQL page size, default 500
    max_pages: optional hard stop for pagination, default 100
    """
    base_url = clean_base_url(kwargs.get('access_key', ''))
    api_key = safe_str(kwargs.get('access_secret', '')).strip()

    if api_key == '':
        print('Onapsis: access_secret is required (API key).')
        return []

    page_size = parse_int(kwargs.get('page_size', DEFAULT_PAGE_SIZE), DEFAULT_PAGE_SIZE)
    max_pages = parse_int(kwargs.get('max_pages', DEFAULT_MAX_PAGES), DEFAULT_MAX_PAGES)

    token = get_access_token(base_url, api_key)
    if token == '':
        return []

    assets_rows = paginate_graphql_list(base_url, token, ASSETS_QUERY, 'assets', page_size, max_pages)
    vuln_rows = paginate_graphql_list(base_url, token, VULNS_QUERY, 'vulnerabilities', page_size, max_pages)

    if assets_rows == None and vuln_rows == None:
        print('Onapsis: unable to query assets or vulnerabilities. Verify API permissions and fields.')
        return []

    asset_map = {}

    if type(assets_rows) == 'list':
        for row in assets_rows:
            if type(row) == 'dict':
                add_asset_from_assets_query(asset_map, row)

    if type(vuln_rows) == 'list':
        attach_vulnerabilities(asset_map, vuln_rows)

    assets = []
    for _, asset in asset_map.items():
        assets.append(asset)

    print('Onapsis: built {} asset(s) from {} asset rows and {} vulnerability rows.'.format(
        len(assets),
        len(assets_rows) if type(assets_rows) == 'list' else 0,
        len(vuln_rows) if type(vuln_rows) == 'list' else 0,
    ))
    return assets
