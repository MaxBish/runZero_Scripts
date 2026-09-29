CONFIG = {
    "id": "runzero-aikido",
    "name": "Aikido Security",
    "type": "inbound",
    "description": "Imports cloud assets, virtual machines, and endpoint devices from Aikido Security.",
    "version": "1",
    "maturity": "alpha",
    "minVersion": "5.1.260818.0",
    "maxPages": 1000,
    "matchBehavior": "no-mac-break no-ip-break no-name-break",
    "params": [
        {"key": "url", "label": "Aikido API URL", "type": "url", "required": False, "default": "https://app.aikido.dev/api/public/v1"},
        {"key": "token_url", "label": "Aikido token URL", "type": "url", "required": False, "default": "https://app.aikido.dev/api/oauth/token"},
        {"key": "client_id", "label": "Client ID", "type": "string", "required": True},
        {"key": "client_secret", "label": "Client secret", "type": "secret", "required": True},
        {"key": "page_size", "label": "Cloud assets per page", "type": "int", "required": False, "default": 100, "min": 10, "max": 100},
    ],
    "includes": {"tls_": OPTIONS_TLS, "http_": OPTIONS_HTTP},
}

load("runzero.types", "ImportAsset", "to_custom_attributes")
load("http", "get_json", "bearer", "oauth2_token", "url_join")
load("kwargs", "require", "get_string", "get_int", "get_http_options")
load("coerce", "as_dict", "as_list")

def _text(value):
    return "" if value == None else str(value).strip()

def _get(url, options, params=None):
    data, err = get_json(url, params=params, **options)
    if err:
        print("aikido: request failed: " + err)
        return None
    return data

def _attrs(record, extra):
    attrs = {}
    for key in record:
        if record.get(key) != None:
            attrs[key] = record.get(key)
    for key in extra:
        if extra.get(key) != None and extra.get(key) != "":
            attrs[key] = extra.get(key)
    return attrs

def _asset(kind, record, name, os_name, os_version, attrs, tags):
    source_id = _text(record.get("id"))
    if not source_id:
        print("aikido: skipping " + kind + " with no id")
        return None
    return ImportAsset(
        id="aikido:{}:{}".format(kind, source_id),
        hostnames=[name] if name else [],
        os=os_name,
        osVersion=os_version,
        assetType=kind,
        tags=tags,
        customAttributes=to_custom_attributes("aikido", attrs, "_"),
    )

def main(*args, **kwargs):
    require(kwargs, "client_id", "client_secret")
    token = oauth2_token(
        token_url=get_string(kwargs, "token_url"),
        client_id=get_string(kwargs, "client_id"),
        client_secret=get_string(kwargs, "client_secret"),
        scope="clouds:read virtual_machines:read endpoint_protection:read",
    )
    base_url = get_string(kwargs, "url").rstrip("/") + "/"
    options = get_http_options(kwargs, "http_", "tls_", {"Authorization": bearer(token)})
    page_size = get_int(kwargs, "page_size", default=100)

    page = 0
    cloud_guard = pager("aikido-cloud-assets")
    while cloud_guard.next():
        response = as_dict(_get(url_join(base_url, "clouds/assets"), options, {"page": page, "limit": page_size}))
        records = as_list(response.get("assets"))
        for record in records:
            record = as_dict(record)
            asset = _asset("cloud", record, _text(record.get("asset_name")), "", "", _attrs(record, {}), ["aikido", "cloud"])
            if asset:
                report_asset(asset)
        if not response.get("hasMore") or not records:
            break
        page += 1

    for record in as_list(_get(url_join(base_url, "virtual-machines"), options)):
        record = as_dict(record)
        asset = _asset("virtual-machine", record, _text(record.get("name")), _text(record.get("os")), _text(record.get("os_version")), _attrs(record, {}), ["aikido", "virtual-machine"])
        if asset:
            report_asset(asset)

    for record in as_list(_get(url_join(base_url, "endpoint-protection/devices"), options)):
        record = as_dict(record)
        asset = _asset("endpoint-device", record, _text(record.get("name")), _text(record.get("os")), "", _attrs(record, {}), ["aikido", "endpoint-device"])
        if asset:
            report_asset(asset)
    return None