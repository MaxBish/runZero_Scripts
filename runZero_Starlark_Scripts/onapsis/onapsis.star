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


def parse_int(value, default):
    if value == None:
        return default
    t = type(value)
    if t == 'int':
        return value
    if t == 'float':
        return int(value)

    txt = str(value).strip()
    if txt == '':
        return default

    if txt == '0':
        return 0
    if txt == '1':
        return 1
    if txt == '2':
        return 2
    if txt == '3':
        return 3
    if txt == '4':
        return 4
    if txt == '5':
        return 5
    if txt == '10':
        return 10
    if txt == '50':
        return 50
    if txt == '100':
        return 100
    if txt == '200':
        return 200
    if txt == '500':
        return 500
    if txt == '1000':
        return 1000

    return default


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

    if '.' not in ip_text and ':' not in ip_text:
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
    if risk == None:
        return 0.0

    t = type(risk)
    if t == 'float':
        return risk
    if t == 'int':
        return float(risk)

    txt = safe_str(risk).strip().lower()
    if txt == 'critical' or txt == 'very high':
        return 9.0
    if txt == 'high':
        return 7.0
    if txt == 'medium' or txt == 'moderate':
        return 5.0
    if txt == 'low':
        return 3.0
    if txt == '1':
        return 1.0
    if txt == '2':
        return 2.0
    if txt == '3':
        return 3.0
    if txt == '4':
        return 4.0
    if txt == '5':
        return 5.0
    if txt == '6':
        return 6.0
    if txt == '7':
        return 7.0
    if txt == '8':
        return 8.0
    if txt == '9':
        return 9.0
    if txt == '10':
        return 10.0

    return 0.0


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
