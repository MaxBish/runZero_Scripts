import requests
import json
import csv
import os

RUNZERO_BASE_URL = "https://console.runZero.com/api/v1.0"
RUNZERO_ORG_ID = "XXXXXX"
RUNZERO_ORG_TOKEN = os.environ["RUNZERO_ORG_TOKEN"]
HEADERS = {"Authorization": f"Bearer {RUNZERO_ORG_TOKEN}"}
OWNERSHIP_TYPE_ID = 'XXXXXXXXX'

def get_runzero_assets():
    """
    Function to get all assets and their respective owners from RunZero.

    Returns:
        asset_list (list): List of all asset IDs
        asset_owner (list): List of all asset owners
    """
    # Search query
    query = 'has:@crowdstrike.dev.lastLoginUser and @crowdstrike.dev.lastLoginUser:="XXXXXXXXX"'    
    url = f"{RUNZERO_BASE_URL}/org/assets"

    # Set the parameters for the API call
    params = {"search": query}

    # Make the API call
    resp = requests.get(url=url, headers=HEADERS, params=params)

    # Get the JSON response
    all_asset_data = resp.json()

    # Extract the asset IDs and owners from the response
    asset_list = [x["id"] for x in all_asset_data]
    asset_owner = [y['foreign_attributes']['XXXXXXX'][0]['XXXXXXXXX'] for y in all_asset_data]

    # Return the asset IDs and owners
    return asset_list, asset_owner

def update_asset_owner(asset_list, asset_owner):
    """
    Updates the owner of each asset in the asset_list with the corresponding owner in the asset_owner list.

    Parameters:
        asset_list (list): List of asset IDs to update.
        asset_owner (list): List of new owners corresponding to each asset ID.

    Returns:
        None
    """
    count = 0 # Initialize a counter to track the current index in the asset_owner list

    for asset_id in asset_list:
        # Construct the URL for updating the asset owner
        update_url = f"{RUNZERO_BASE_URL}/org/assets/{asset_id}/owners"
        
        # Prepare the payload with ownership type and new owner email
        payload = {"ownership_type_id": OWNERSHIP_TYPE_ID, "owner": asset_owner[count]}
        
        # Set the parameters for the API call, including organization ID
        params = {'asset_id': asset_id, "_oid": RUNZERO_ORG_ID}
        
        # Make the PATCH request to update the asset owner
        response = requests.patch(update_url, json=payload, headers=HEADERS, params=params)

        # Check the response status
        if response.status_code == 200:
            print(f"Successfully updated owner for asset {asset_id} to {asset_owner[count]}")
            count += 1  # Move to the next owner in the list
        else:
            print(f"Failed to update owner for asset {asset_id}. Status code: {response.status_code}")
            print("Response:", response.text)

def main():
    """
    Main entry point for the script. Gets the list of assets from RunZero and
    their owners, then updates the owners based on the mapping defined in the
    get_runzero_assets function.
    """
    # Get the list of assets and their owners
    asset_list, asset_owner = get_runzero_assets()

    # Update the owners of the assets
    update_asset_owner(asset_list, asset_owner)

    # Return from the main function
    return

if __name__ == "__main__":
    main()