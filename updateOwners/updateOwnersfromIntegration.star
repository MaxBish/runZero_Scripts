"""Update runZero asset owners from CrowdStrike last login user data."""

load("json", json_encode="encode", json_decode="decode")
load("http", http_get="get", http_patch="patch")

def get_runzero_assets(api_token):
    """Fetch runZero asset IDs and owner values from CrowdStrike attributes.

    Args:
      api_token: Org API token used to query runZero assets.

    Returns:
      A tuple of two lists: (asset_list, asset_owner).
    """
    query = 'has:@crowdstrike.dev.lastLoginUser'
    url = "https://console.runZero.com/api/v1.0/org/assets"
    headers = {"Authorization": "Bearer {}".format(api_token)}
    params = {"search": query, "fields": "id,foreign_attributes"}

    print("Fetching assets from RunZero API...")
    response = http_get(url=url, headers=headers, params=params, timeout=300)

    if response.status_code != 200:
        print("Failed to get assets. Status code: {}".format(response.status_code))
        print("Response:", response.body)
        return [], []

    all_asset_data = json_decode(response.body)

    asset_list, asset_owner = [], []

    for asset in all_asset_data:
        asset_list.append(asset.get("id", ""))
        asset_owner.append(asset.get('foreign_attributes', {}).get('@crowdstrike.dev', [{}])[0].get('lastLoginUser', ""))

    return asset_list, asset_owner

def update_asset_owner(api_token, asset_list, asset_owner, ownership_type_id):
    """Patch each asset owner in runZero using the provided ownership type.

    Args:
      api_token: Org API token used to patch runZero assets.
      asset_list: List of runZero asset IDs.
      asset_owner: List of owner values corresponding to asset_list.
      ownership_type_id: runZero ownership type ID for the patch payload.
    """
    for asset_id, owner_name in zip(asset_list, asset_owner):
        if not owner_name:
            print("Skipping asset {} because no owner value was found.".format(asset_id))
            continue

        update_url = "https://console.runZero.com/api/v1.0/org/assets/{}/owners".format(asset_id)

        payload = {
            "ownerships": [
                {
                    "ownership_type_id": ownership_type_id,
                    "owner": owner_name
                }
            ]
        }

        headers = {"Authorization": "Bearer {}".format(api_token), "Content-Type": "application/json"}

        response = http_patch(update_url, headers=headers, body=bytes(json_encode(payload)), timeout=300)

        if response.status_code == 200:
            print("Successfully updated owner for asset {} to {}".format(asset_id, owner_name))
        else:
            print("Failed to update owner for asset {}. Status code: {}".format(asset_id, response.status_code))
            print("Response:", response.body)

def main(**kwargs):
    """Run owner updates for assets that include CrowdStrike last login data.

    Args:
      **kwargs: Task parameters from runZero, including access_secret
        for the Org API token and access_key for the ownership type to set.

    Returns:
      An empty list (this task updates assets directly and does not import assets).
    """
    api_token = kwargs.get("access_secret")
    ownership_type_id = kwargs.get("access_key")

    if not api_token:
        print("Missing required parameters: access_secret (API token)")
        return []

    if not ownership_type_id:
        print("Missing required parameter: access_key (ownership type ID)")
        return []

    asset_list, asset_owner = get_runzero_assets(api_token)

    if not asset_list:
        print("No assets found to update.")
        return []

    update_asset_owner(api_token, asset_list, asset_owner, ownership_type_id)
    return []