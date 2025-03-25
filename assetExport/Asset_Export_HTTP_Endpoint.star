## Asset Export to HTTP Endpoint (Starlark)

load('json', json_encode='encode', json_decode='decode')
load('http', http_post='post', http_get='get')

# Configuration
HTTP_ENDPOINT = "<UPDATE_ME>"
BASE_URL = "https://console.runZero.com/api/v1.0"
SEARCH = "id:XXXXXXXXXXXX"

## Constants
software_params = ['software_vendor,software_product,software_version']
vuln_params = ['vulnerability_name,vulnerability_cve,vulnerability_risk,vulnerability_exploitable']

def fetch_assets(headers):
    """Retrieve assets from the runZero API based on the SEARCH query.

    Args:
        headers (dict): The headers to include in the API request.

    Returns:
        list: A list of assets retrieved from the runZero API.
    """
    # Retrieve assets from the runZero API based on the SEARCH query.
    url = "{}/org/assets?{}".format(BASE_URL, url_encode({"search": SEARCH}))
    response = http_get(url, headers=headers, timeout = 600)
    
    if response.status_code == 200:
        assets = json_decode(response.body)
        print("Retrieved {} assets from runZero.".format(len(assets)))
        return assets
    else:
        print("runZero did not return any assets - status code {}".format(response.status_code))
        return None

def fetch_software(headers, asset_id):
    """Retrieve software information for a specific asset.  
    
    Args:
      headers: A dictionary of HTTP headers to include in the API request.
      asset_id: The ID of the asset for which to retrieve software information.

    Returns:
      list: A list of software information for the specified asset, or an empty list if the request fails.
    """
    url = "{}/export/org/software.json?{}".format(BASE_URL, url_encode({"search": "asset_id:{}".format(asset_id), "fields": software_params}))
    response = http_get(url, headers=headers)
    if response.status_code == 200:
        software_data = json_decode(response.body)
        return software_data
    else:
        print("Failed to fetch software for asset {} - status code {}".format(asset_id, response.status_code))
        return None

def fetch_vulnerabilities(headers, asset_id):
    """Retrieve vulnerability information for a specific asset.

    Args:
        headers (dict): A dictionary of HTTP headers to include in the API request.
        asset_id (str): The ID of the asset for which to retrieve vulnerability information.

    Returns:
        list: A list of vulnerability information for the specified asset, or an empty list if the request fails.
    """
    url = "{}/export/org/vulnerabilities.json?{}".format(BASE_URL, url_encode({"search": "asset_id:{}".format(asset_id), "fields": vuln_params}))
    response = http_get(url, headers=headers)
    if response.status_code == 200:
        vulnerability_data = json_decode(response.body)
        return vulnerability_data
    else:
        print("Failed to fetch vulnerabilities for asset {} - status code {}".format(asset_id, response.status_code))
        return []

def send_to_http_endpoint(assets):
    """Transmit asset data to the specified HTTP endpoint.

    Args:
      assets: A list of asset data to be transmitted to the HTTP endpoint.
    """
    print("Sending {} assets to HTTP endpoint".format(len(assets)))
    batch_size = 500
    if len(assets) > 0:
        for i in range(0, len(assets), batch_size):
            batch = assets[i:i + batch_size]
            tmp = ""
            for a in batch:
                tmp = tmp + "{}\n".format(json_encode(a))
            post_to_http_endpoints = http_post(HTTP_ENDPOINT, body=bytes(tmp))

    else:
        print("No assets found")

def main(**kwargs):
    """Main function to orchestrate the fetching and sending of asset data.

    Args:
      **kwargs: A dictionary of keyword arguments. Currently, it expects 'access_secret' key
        which is used to construct the Authorization header for API requests.
    """
    headers = {"Authorization": "Bearer {}".format(kwargs["access_secret"])}
    assets = fetch_assets(headers)
    for asset in assets:
        count = 0
        asset_id = asset.get("id", "")
        asset_address = asset.get("addresses", [""])[0]
        print("Getting vuln and software data for IP: {}".format(asset_address))

        # Fetch and append software data
        software_data = fetch_software(headers, asset_id)
        if software_data:
            assets[count]["software"] = software_data

        # Fetch and append vulnerability data
        vulnerability_data = fetch_vulnerabilities(headers, asset_id)
        if vulnerability_data:
            assets[count]["vulnerabilities"] = vulnerability_data

        count = count + 1

    if assets:
        send_to_http_endpoint(assets)