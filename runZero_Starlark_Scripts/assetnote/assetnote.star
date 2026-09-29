CONFIG = {
    "id": "runzero-assetnote",
    "name": "AssetNote",
    "type": "inbound",
    "description": "Imports external-facing assets from AssetNote.",
    "version": "1",
    "maturity": "alpha",
    "minVersion": "5.1.260818.0",
    "maxPages": 100000,
    "matchBehavior": "no-mac-break no-ip-break no-name-break",
    "params": [
        {"key": "instance", "label": "AssetNote instance", "type": "string", "required": True},
        {"key": "api_key", "label": "API key", "type": "secret", "required": True},
        {"key": "url", "label": "GraphQL URL override", "type": "url", "required": False},
        {"key": "page_size", "label": "Assets per page", "type": "int", "required": False, "default": 25, "min": 1, "max": 25},
    ],
    "includes": {"tls_": OPTIONS_TLS, "http_": OPTIONS_HTTP},
}

load("runzero.types", "ImportAsset", "to_custom_attributes")
load("http", "post_json")
load("kwargs", "require", "get_string", "get_int", "get_http_options")
load("coerce", "as_dict", "as_list", "as_text")
load("net", "clean_hostnames", "network_interface")
load("re", re_match="match")
load("time", "parse_ts")

ASSETS_QUERY = """{{
    assets(s:[{{field:"id",dir:ASC}}],count:{page_size},page:{page}) {{
    edges {{ node {{
      __typename
      ... on BaseAsset {{
        id
        humanName
        host
        assetType
        assetGroupId
        assetGroupName
        exposureRating
        isOnline
        isMonitored
        verifiedStatus
        importance
        created
        lastUpdated
      }}
      ... on IpAsset {{ ipAddress }}
      ... on SubdomainAsset {{ subdomain }}
    }} }}
    pageInfo {{ hasNextPage }}
  }}
}}"""

def _asset(node, instance):
    source_id = as_text(node.get("id")).strip()
    if not source_id:
        print("assetnote: skipping asset without an id")
        return None

    typename = as_text(node.get("__typename"))
    asset_type = {"IpAsset": "ip", "SubdomainAsset": "subdomain", "CloudAsset": "cloud"}.get(typename, "asset")
    attrs = {}
    for key in ["humanName", "assetType", "assetGroupId", "assetGroupName", "exposureRating", "isOnline", "isMonitored", "verifiedStatus", "importance"]:
        if node.get(key) != None:
            attrs[key] = node.get(key)

    address = as_text(node.get("ipAddress"))
    interface = network_interface(ips=[address]) if address else None
    return ImportAsset(
        id="assetnote:{}:{}".format(instance, source_id),
        assetType=asset_type,
        hostnames=clean_hostnames([node.get("host"), node.get("subdomain")]),
        networkInterfaces=[interface] if interface else [],
        firstSeenTS=parse_ts(node.get("created")),
        lastSeenTS=parse_ts(node.get("lastUpdated")),
        customAttributes=to_custom_attributes("assetnote", attrs, "_"),
    )

def main(*args, **kwargs):
    require(kwargs, "instance", "api_key")
    instance = get_string(kwargs, "instance").strip().lower()
    if len(instance) > 63 or not re_match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$", instance):
        fail("assetnote: instance must be a single DNS label")

    endpoint = get_string(kwargs, "url") or "https://{}.assetnotecloud.com/api/v2/graphql".format(instance)
    options = get_http_options(kwargs, "http_", "tls_", {
        "X-ASSETNOTE-API-KEY": get_string(kwargs, "api_key"),
        "Accept": "application/json",
    })
    page_size = get_int(kwargs, "page_size", default=25)
    page = 1
    previous_id = ""
    pages = pager("assetnote-assets")
    while pages.next():
        response, err = post_json(endpoint, json={"query": ASSETS_QUERY.format(page_size=page_size, page=page)}, **options)
        if err:
            fail("assetnote: failed to fetch assets: {}".format(err))
        response = as_dict(response)
        if response.get("errors"):
            fail("assetnote: GraphQL rejected the assets query")
        assets = as_dict(as_dict(response.get("data")).get("assets"))
        page_info = as_dict(assets.get("pageInfo"))
        if "hasNextPage" not in page_info or type(assets.get("edges")) != "list":
            fail("assetnote: malformed assets page or pagination")

        edges = as_list(assets.get("edges"))
        if page_info.get("hasNextPage") and not edges:
            fail("assetnote: empty assets page with more pages indicated")
        for edge in edges:
            node = as_dict(as_dict(edge).get("node"))
            source_id = as_text(node.get("id")).strip()
            if source_id and source_id == previous_id:
                continue
            asset = _asset(node, instance)
            if asset:
                report_asset(asset)
                previous_id = source_id
        if not page_info.get("hasNextPage"):
            break
        page += 1
    return None