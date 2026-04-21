"""
Deletes runZero assets that match a configured search query.
Runs as a runZero task, receiving the API token via kwargs.

Set SEARCH to any valid runZero asset search query before running.
"""

load('json', json_encode='encode', json_decode='decode')
load('http', http_get='get', http_delete='delete')

BASE_URL = "https://console.runZero.com/api/v1.0"
SEARCH = "last_seen:>7days"

def get_delete_ids(headers):
    """Query the runZero export API and return asset IDs matching SEARCH.

    Only the 'id' field is requested to keep the response payload small.
    Returns an empty list if the request fails.

    Args:
      headers: dict containing the Authorization and Content-Type headers.

    Returns:
      A list of asset ID strings matching SEARCH, or [] on failure.
    """
    url = BASE_URL + "/export/org/assets.json"
    params = {"search": SEARCH, "fields": "id"}
    response = http_get(url=url, headers=headers, params=params, timeout=3600)

    if response.status_code != 200:
        print("Failed to fetch assets. Status code: {}".format(response.status_code))  # @unused
        print("Response: {}".format(response.body))  # @unused
        return []

    assets_json = json_decode(response.body)
    assets = []

    # Filter out any entries that are missing an ID to avoid bad delete requests.
    for asset in assets_json:
        asset_id = asset.get("id", "")
        if asset_id:
            assets.append(asset_id)

    print("Found {} assets matching search: {}".format(len(assets), SEARCH))  # @unused
    return assets


def delete_assets(assets, headers):
    """Send a single bulk delete request for the given list of asset IDs.

    A 204 response means all assets were successfully deleted.
    Any other status code is treated as a failure and the response body is logged.

    Args:
      assets: list of asset ID strings to delete.
      headers: dict containing the Authorization and Content-Type headers.
    """
    url = BASE_URL + "/org/assets/bulk/delete"
    print("Deleting {} assets matching search: {}".format(len(assets), SEARCH))  # @unused
    response = http_delete(url, headers=headers, body=bytes(json_encode({"asset_ids": assets})), timeout=3600)

    if response.status_code == 204:
        print("Deleted all assets matching this search: {}".format(SEARCH))  # @unused
    else:
        print("Failed to delete assets. Status code: {}".format(response.status_code))  # @unused
        print("Response: {}".format(response.body))  # @unused


def main(**kwargs):
    """Fetch and delete all runZero assets matching SEARCH.

    Entrypoint called by the runZero task runner. Exits early if
    'access_secret' is missing or no matching assets are found.

    Args:
      **kwargs: keyword arguments provided by the runZero task runner.
        access_secret: Org API token configured in the task settings.

    Returns:
      An empty list (runZero tasks that modify assets return no imports).
    """
    rz_org_token = kwargs.get('access_secret')
    if not rz_org_token:
        print("Missing required parameter: access_secret")  # @unused
        return []

    headers = {"Authorization": "Bearer {}".format(rz_org_token), "Content-Type": "application/json"}

    # Fetch the list of asset IDs to delete, then delete them if any were found.
    assets = get_delete_ids(headers=headers)
    if assets:
        delete_assets(assets=assets, headers=headers)
    return []