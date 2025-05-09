## Asset Export to HTTP Endpoint (Starlark)

load('runzero.types', 'ImportAsset', 'NetworkInterface')
load('json', json_encode='encode', json_decode='decode')
load('http', http_post='post', http_get='get', 'url_encode')

# Configuration
HTTP_ENDPOINT = "<UPDATE_ME>"
BASE_URL = "https://console.runZero.com/api/v1.0"
SEARCH = "has_ipv4:true"

def fetch_assets(headers):
    """Fetches assets from the runZero API.

    Args:
        headers: A dictionary of HTTP headers to include in the request.

    Returns:
        A list of assets retrieved from the runZero API, or None if the request fails.
    """
    url = "{}/export/org/assets.json?{}".format(BASE_URL, url_encode({"search": SEARCH}))
    response = http_get(url, headers=headers, timeout=600)
   
    if response.status_code == 200:
        assets = json_decode(response.body)
        print(assets)
        print("Retrieved {} assets from runZero.".format(len(assets)))
        return assets
    else:
        print("runZero did not return any assets - status code {}".format(response.status_code))
        return None

def fetch_software(headers, asset_id):
    """Fetches software data for a given asset ID from the runZero API.

    Args:
        headers: A dictionary of HTTP headers to include in the request.
        asset_id: The ID of the asset to fetch software data for.

    Returns:
        A list of software data for the given asset ID, or an empty list if the request fails.
    """
    url = "{}/export/org/software.json?{}".format(BASE_URL, url_encode({"search": "asset_id:{}".format(asset_id)}))
    response = http_get(url, headers=headers)
    if response.status_code == 200:
        software_data = json_decode(response.body)
        return software_data
    else:
        print("Failed to fetch software for asset {} - status code {}".format(asset_id, response.status_code))
        return []

def fetch_vulnerabilities(headers, asset_id):
    """
    Fetches vulnerability data for a given asset ID from the runZero API.

    Args:
        headers: A dictionary of HTTP headers to include in the request.
        asset_id: The ID of the asset to fetch vulnerability data for.

    Returns:
        A list of vulnerability data for the given asset ID, or an empty list if the request fails.
    """
    url = "{}/export/org/vulnerabilities.json?{}".format(BASE_URL, url_encode({"search": "asset_id:{}".format(asset_id)}))
    response = http_get(url, headers=headers)
    if response.status_code == 200:
        vulnerability_data = json_decode(response.body)
        return vulnerability_data
    else:
        print("Failed to fetch vulnerabilities for asset {} - status code {}".format(asset_id, response.status_code))
        return []

def send_to_http_endpoint(assets):
    """
    Sends a list of assets to an HTTP endpoint in batches.

    Args:
        assets (list): A list of assets to be sent to the HTTP endpoint.

    Returns:
        None
    """
    print("Sending {} assets to HTTP endpoint".format(len(assets)))
    batch_size = 500
    if len(assets) > 0:
        for i in range(0, len(assets), batch_size):
            batch = assets[i:i + batch_size]
            tmp = "[{}]".format(",\n".join([json_encode(a) for a in batch]))
            response = http_post(HTTP_ENDPOINT, body=bytes(tmp), timeout = 600)

            if response.status_code == 200:
                if "Success" in response.body:
                    print("Batch {}-{} sent successfully.".format(i + 1, i + len(batch)))
                else:
                    print("Error in response: {}".format(response.body))
            else:
                print("Failed to send batch {}-{} - HTTP status {}".format(i + 1, i + len(batch), response.status_code))
                print("Response body: {}".format(response.body))
           
    else:
        print("No assets found")

def main(*args, **kwargs):
    """Main function to fetch and process assets."""
    headers = {"Authorization": "Bearer {}".format(kwargs["access_secret"])}
    assets = fetch_assets(headers)
    for asset in assets:
        asset_id = asset.get("id", "")
        asset_address = asset.get("addresses", [""])[0]
        print("Getting vuln and software data for IP: {}".format(asset_address))

        # Fetch and append software data
        software_data = fetch_software(headers, asset_id)
        if software_data:
            asset["software"] = software_data

        # Fetch and append vulnerability data
        vulnerability_data = fetch_vulnerabilities(headers, asset_id)
        if vulnerability_data:
            asset["vulnerabilities"] = vulnerability_data

    if assets:
        send_to_http_endpoint(assets)
       
    # Return an empty list to satisfy the ImportAsset return requirement
    return []