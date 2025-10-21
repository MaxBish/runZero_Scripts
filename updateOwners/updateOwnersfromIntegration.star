load("runzero.types", "ImportAsset")
load("json", json_encode="encode", json_decode="decode")
load("http", http_get="get", http_patch="patch")

def get_runzero_assets(api_token):
    """
    Function to get all assets and their respective owners from a RunZero API.

    Returns:
        A tuple containing two lists: asset_list (list) and asset_owner (list).
    """
    query = 'has:@crowdstrike.dev.lastLoginUser'
    url = "https://console.runZero.com/api/v1.0/org/assets"

    # Set the headers for the API call
    headers = {"Authorization": "Bearer {}".format(api_token)}

    # Set the parameters for the API call
    params = {"search": query, "fields": "id,foreign_attributes"}

    # Make the API call
    print("Fetching assets from RunZero API...")
    response = http_get(url=url, headers=headers, params=params, timeout=300)

    # Check for a successful response
    if response.status_code != 200:
        print("Failed to get assets. Status code: {}".format(response.status_code))
        print("Response:", response.body)
        return [], []

    all_asset_data = json_decode(response.body)

    asset_list, asset_owner = [], []

    for asset in all_asset_data:
        asset_list.append(asset.get("id", ""))
        asset_owner.append(asset.get('foreign_attributes', {}).get('@crowdstrike.dev', [{}])[0].get('lastLoginUser',""))

    # Return the asset IDs and owners
    return asset_list, asset_owner

def update_asset_owner(api_token, asset_list, asset_owner, ownership_type_id):
    """
    Updates the owner of each asset in the asset_list with the corresponding owner
    in the asset_owner list.
    """
    # Use zip to iterate through both lists simultaneously
    for asset_id, owner_name in zip(asset_list, asset_owner):
        # The URL is correctly set for the owners endpoint
        update_url = "https://console.runZero.com/api/v1.0/org/assets/{}/owners".format(asset_id)
        
        # -- CORRECTED: The payload is now a dictionary with an "ownerships" key. --
        payload = {
            "ownerships": [
                {
                    "ownership_type_id": ownership_type_id,
                    "owner": owner_name
                }
            ]
        }
        
        # Set the headers for the API call
        headers = {"Authorization": "Bearer {}".format(api_token), "Content-Type": "application/json"}
        
        # Make the PATCH request to update the asset owner
        response = http_patch(update_url, headers=headers, body=bytes(json_encode(payload)), timeout=300)

        # Check the response status
        if response.status_code == 200:
            print("Successfully updated owner for asset {} to {}".format(asset_id, owner_name))
        else:
            print("Failed to update owner for asset {}. Status code: {}".format(asset_id, response.status_code))
            print("Response:", response.body)

def main(**kwargs):
    """
    Main entry point for the script.
    """
    # Retrieve credentials and parameters from kwargs
    api_token = kwargs.get("access_secret")
    
    # This is a placeholder for the ownership type ID
    ownership_type_id = "XXXXXXXXXXXXX"

    if not api_token:
        print("Missing required parameters: access_secret (API token)")
        return []

    # Get the list of assets and their owners
    asset_list, asset_owner = get_runzero_assets(api_token)

    if not asset_list:
        print("No assets found to update.")
        return []

    # Update the owners of the assets
    update_asset_owner(api_token, asset_list, asset_owner, ownership_type_id)

    # Return an empty list as this script modifies assets directly, not imports them
    return []