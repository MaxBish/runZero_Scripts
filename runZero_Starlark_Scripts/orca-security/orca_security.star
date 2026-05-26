
"""
Module for importing assets from Orca Security via the Serving Layer API.

This integration supports querying a configurable set of asset models from Orca's Serving Layer API.
If no asset_models parameter is provided, it defaults to the following recommended list (per customer insight):
    AwsEc2Instance, AwsRdsInstance, AwsEksCluster, AwsS3Bucket, AwsLambdaFunction,
    AwsWorkspacesWorkspace, AwsApiGateway, AwsAlbLoadBalancer, AwsNlbLoadBalancer, AwsElbLoadBalancer
If asset_models is empty or None, the script will auto-discover asset models from the schema.

Reference: https://docs.orcasecurity.io/docs/translating-asset-queries-to-the-serving-layer-api
"""

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('http', http_post='post', http_get='get')
load('net', 'ip_address')
load('flatten_json', 'flatten')

BASE_URL = "https://api.orcasecurity.io/api"
QUERY_ENDPOINT = "/serving-layer/query"
SCHEMA_ENDPOINT = "/serving-layer/schema"
PAGE_SIZE = 100
MAX_PAGES = 1000
MAX_QUERY_TIER = 2

def append_unique(values, value):
    """Append a non-empty value to a list if it is not already present."""
    # DEBUG
    print("append_unique called with value:", value)
    if value == None:
        return
    if type(value) == "string" and value == "":
        return
    if value not in values:
        values.append(value)

def get_candidate_nodes(item):
    """Return the item and any nested dict nodes that may contain asset fields."""
    print("get_candidate_nodes called with item:", item)
    nodes = []
    if type(item) != "dict":
        return nodes

    nodes.append(item)
    for key in ['data', 'properties', 'entity', 'metadata', 'asset']:
        value = item.get(key)
        if type(value) == "dict":
            nodes.append(value)
    print("get_candidate_nodes returning nodes:", nodes)
    return nodes

def get_first_value(nodes, keys):
    """Return the first non-empty value found across a set of nodes and keys."""
    print("get_first_value called with nodes:", nodes, "keys:", keys)
    for node in nodes:
        for key in keys:
            value = node.get(key)
            print("Checking node key:", key, "value:", value)
            if value != None and value != "":
                print("get_first_value returning:", value)
                return value
    print("get_first_value returning None")
    return None

def append_node_list_values(values, nodes, keys):
    """Collect list or scalar values from matching keys into a deduplicated list."""
    print("append_node_list_values called with nodes:", nodes, "keys:", keys)
    for node in nodes:
        for key in keys:
            raw = node.get(key)
            print("Checking node key:", key, "raw:", raw)
            if type(raw) == "list":
                for value in raw:
                    append_unique(values, value)
            elif raw != None and raw != "":
                append_unique(values, raw)

def build_network_interfaces(item):
    """Extract network interface data from a Serving Layer asset record."""
    print("build_network_interfaces called with item:", item)
    nodes = get_candidate_nodes(item)
    all_ips = []
    ip4s = []
    ip6s = []
    macs = []

    append_node_list_values(all_ips, nodes, ['PublicIps', 'public_ips', 'PrivateIps', 'private_ips', 'IpAddresses', 'ip_addresses'])
    append_node_list_values(macs, nodes, ['MacAddresses', 'mac_addresses', 'MacAddress', 'mac_address'])

    for ip in all_ips:
        if type(ip) != "string":
            continue
        addr = ip_address(ip)
        print("Parsed IP address:", addr)
        if addr.version == 4 and addr not in ip4s:
            ip4s.append(addr)
        elif addr.version == 6 and addr not in ip6s:
            ip6s.append(addr)

    mac_val = None
    if len(macs) > 0:
        mac_val = macs[0]

    if len(ip4s) == 0 and len(ip6s) == 0 and mac_val == None:
        print("No network interfaces found.")
        return []

    print("Returning network interface:", mac_val, ip4s, ip6s)
    return [NetworkInterface(macAddress=mac_val, ipv4Addresses=ip4s, ipv6Addresses=ip6s)]

def collect_attribute_names(node, names):
    """Collect attribute names from a schema node for model classification."""
    print("collect_attribute_names called with node:", node)
    if type(node) != "dict":
        return

    for field_key in ['attributes', 'fields', 'properties', 'columns']:
        field_value = node.get(field_key)
        print("Checking field_key:", field_key, "field_value:", field_value)
        if type(field_value) == "dict":
            for key in field_value.keys():
                append_unique(names, key)
        elif type(field_value) == "list":
            for entry in field_value:
                if type(entry) == "string":
                    append_unique(names, entry)
                elif type(entry) == "dict":
                    name = entry.get('name') or entry.get('field') or entry.get('key')
                    append_unique(names, name)

def is_asset_model(model_name, node):
    """Heuristically classify a Serving Layer schema model as an asset model."""
    print("is_asset_model called with model_name:", model_name)
    if type(model_name) != "string" or model_name == "":
        return False

    model_name_lower = model_name.lower()
    excluded_terms = [
        'alert', 'cve', 'vulnerability', 'finding', 'remediation', 'log', 'event',
        'attackpath', 'blast', 'permission', 'policy', 'malware', 'identity', 'token',
    ]
    for term in excluded_terms:
        if term in model_name_lower:
            print("Model excluded by term:", term)
            return False

    category = node.get('category') or node.get('entity_category') or node.get('domain')
    if category != None and 'asset' in str(category).lower():
        print("Model included by category:", category)
        return True

    attribute_names = []
    collect_attribute_names(node, attribute_names)
    print("Attribute names found:", attribute_names)
    for indicator in ['asset_unique_id', 'cloud_provider', 'cloud_account_id', 'name', 'type']:
        if indicator in attribute_names:
            print("Model included by indicator:", indicator)
            return True

    included_terms = [
        'instance', 'asset', 'bucket', 'cluster', 'database', 'repository', 'loadbalancer',
        'volume', 'disk', 'node', 'pod', 'vm', 'virtualmachine', 'container', 'image',
        'service', 'subscription', 'project', 'function', 'lambda', 'host', 'server',
    ]
    for term in included_terms:
        if term in model_name_lower:
            print("Model included by term:", term)
            return True

    print("Model not classified as asset model:", model_name)
    return False

def collect_asset_models(node, models, key_hint=None):
    """Walk a schema tree and accumulate likely asset model names."""
    print("collect_asset_models called with node:", node, "key_hint:", key_hint)
    if type(node) == "dict":
        model_name = node.get('name') or node.get('model') or node.get('model_name') or key_hint
        if is_asset_model(model_name, node):
            append_unique(models, model_name)

        for key, value in node.items():
            collect_asset_models(value, models, key)
    elif type(node) == "list":
        for value in node:
            collect_asset_models(value, models, key_hint)

def discover_asset_models(headers):
    """Discover asset-capable Serving Layer models from the Orca schema endpoint."""
    print("discover_asset_models called with headers:", headers)
    response = http_get(BASE_URL + SCHEMA_ENDPOINT, headers=headers, timeout=300)
    print("Schema endpoint response status:", response.status_code)
    if response.status_code != 200:
        print("Failed to get schema, status:", response.status_code)
        return []

    schema_data = json_decode(response.body)
    print("Decoded schema data:", schema_data)
    if type(schema_data) != "dict":
        return []

    schema_root = schema_data.get('data')
    if type(schema_root) != "dict":
        schema_root = schema_data

    models = []
    assets_section = schema_root.get('assets')
    if assets_section != None:
        collect_asset_models(assets_section, models)

    if len(models) == 0 and schema_root.get('models') != None:
        collect_asset_models(schema_root.get('models'), models)

    if len(models) == 0:
        collect_asset_models(schema_root, models)

    print("Discovered asset models:", models)
    return models

def build_query_payload(models, start_at_index):
    """Build a documented Serving Layer object_set query payload."""
    print("build_query_payload called with models:", models, "start_at_index:", start_at_index)
    payload = {
        'query': {
            'models': models,
            'type': 'object_set',
        },
        'limit': PAGE_SIZE,
        'start_at_index': start_at_index,
        'max_tier': MAX_QUERY_TIER,
        'additional_models': [],
        'order_by': [],
        'group_by': [],
        'group_by_aggregations': [],
        'count': False,
        'use_cache': False,
    }
    print("build_query_payload returning:", payload)
    return payload

def extract_query_items(data):
    """Extract a list of result objects from known Serving Layer response shapes."""
    print("extract_query_items called with data:", data)
    if type(data) != "dict":
        return []

    for key in ['data', 'objects', 'results', 'items']:
        value = data.get(key)
        print("Checking key:", key, "value:", value)
        if type(value) == "list":
            print("extract_query_items returning list for key:", key)
            return value
        if type(value) == "dict":
            for nested_key in ['data', 'objects', 'results', 'items']:
                nested_value = value.get(nested_key)
                if type(nested_value) == "list":
                    print("extract_query_items returning nested list for key:", nested_key)
                    return nested_value
    print("extract_query_items returning empty list")
    return []

def query_assets(headers, models):
    """Query Orca Serving Layer for all pages of the requested asset models."""
    print("query_assets called with models:", models)
    assets = []
    start_at_index = 0

    for page in range(MAX_PAGES):
        print("Querying page:", page, "start_at_index:", start_at_index)
        payload = build_query_payload(models, start_at_index)
        response = http_post(
            BASE_URL + QUERY_ENDPOINT,
            headers=headers,
            body=bytes(json_encode(payload)),
            timeout=300,
        )
        print("Query response status:", response.status_code)
        if response.status_code != 200:
            print("Query failed, status:", response.status_code)
            break

        data = json_decode(response.body)
        print("Decoded query response:", data)
        page_items = extract_query_items(data)
        print("Extracted page_items:", page_items)
        if len(page_items) == 0:
            print("No more items, breaking.")
            break

        for item in page_items:
            assets.append(item)

        if len(page_items) < PAGE_SIZE:
            print("Last page reached.")
            break
        start_at_index = start_at_index + len(page_items)

    print("Total assets collected:", len(assets))
    return assets

def build_custom_attributes(item):
    """Flatten useful record fields into runZero custom attributes."""
    print("build_custom_attributes called with item:", item)
    custom_attrs = {}
    for node in get_candidate_nodes(item):
        flat_data = flatten(node)
        print("Flattened node:", flat_data)
        if type(flat_data) != "dict":
            continue

        for key, value in flat_data.items():
            if value == None:
                continue
            if len(custom_attrs) >= 1024:
                print("Custom attribute limit reached.")
                return custom_attrs
            custom_attrs[str(key)] = str(value)

    if type(item) == "dict":
        for key in ['model', 'asset_unique_id', 'cloud_provider', 'cloud_account_id', 'type']:
            value = item.get(key)
            if value != None and len(custom_attrs) < 1024:
                custom_attrs[key] = str(value)

    print("Returning custom_attrs:", custom_attrs)
    return custom_attrs

def map_item_to_asset(item):
    """Map a Serving Layer result object to a runZero ImportAsset."""
    print("map_item_to_asset called with item:", item)
    nodes = get_candidate_nodes(item)
    asset_id = get_first_value(nodes, ['asset_unique_id', 'id', 'base_id', 'uuid'])
    print("Asset ID:", asset_id)
    if asset_id == None:
        print("No asset_id found, skipping item.")
        return None

    hostnames = []
    for key in ['Name', 'name', 'Hostname', 'hostname', 'asset_name', 'asset_display_name', 'public_dns_name', 'private_dns_name']:
        value = get_first_value(nodes, [key])
        append_unique(hostnames, value)
    print("Hostnames:", hostnames)

    asset = ImportAsset(
        id=str(asset_id),
        hostnames=hostnames,
        os=get_first_value(nodes, ['DistributionName', 'os_distribution', 'asset_distribution_name', 'os', 'operating_system']),
        osVersion=get_first_value(nodes, ['DistributionVersion', 'os_version', 'asset_distribution_version', 'operating_system_version']),
        networkInterfaces=build_network_interfaces(item),
        customAttributes=build_custom_attributes(item),
    )
    print("Returning ImportAsset:", asset)
    return asset


def main(**kwargs):
    """
    Import Orca assets into runZero using Serving Layer schema and queries.
    
    Parameters:
        access_secret (str): Orca API token (required)
        asset_models (list, optional): List of asset model names to query. If not provided, defaults to recommended list. If empty, auto-discovers models.
    """
    print("main called with kwargs:", kwargs)
    api_token = kwargs.get('access_secret')
    if not api_token:
        print("No API token provided.")
        return []

    # Default asset models per customer insight
    default_asset_models = [
        'AwsEc2Instance',
        'AwsRdsInstance',
        'AwsEksCluster',
        'AwsS3Bucket',
        'AwsLambdaFunction',
        'AwsWorkspacesWorkspace',
        'AwsApiGateway',
        'AwsAlbLoadBalancer',
        'AwsNlbLoadBalancer',
        'AwsElbLoadBalancer',
    ]

    # Always set headers first
    headers = {
        'Authorization': 'Token ' + api_token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    }
    print("Headers:", headers)

    # Allow asset_models to be passed as a parameter
    asset_models = kwargs.get('asset_models')
    print("asset_models param:", asset_models)
    if asset_models == None:
        models = default_asset_models
        print("Using default asset models:", models)
    elif type(asset_models) == "list" and len(asset_models) > 0:
        models = asset_models
        print("Using provided asset models:", models)
    else:
        # If asset_models is an empty list, fall back to discovery
        models = discover_asset_models(headers)
        print("Discovered asset models:", models)
        if len(models) == 0:
            print("No asset models found.")
            return []

    raw_assets = query_assets(headers, models)
    print("Raw assets:", raw_assets)
    assets = []
    seen_ids = []

    for item in raw_assets:
        asset = map_item_to_asset(item)
        if asset == None or asset.id in seen_ids:
            print("Skipping asset (None or duplicate):", asset)
            continue
        seen_ids.append(asset.id)
        assets.append(asset)
        print("Added asset:", asset)

    print("Returning assets:", assets)
    return assets