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

    ## Search query
    query = 'XXXXXXXXX'    
    url = f"{RUNZERO_BASE_URL}/org/assets"

    params = {"search": query}

    resp = requests.get(url=url, headers=HEADERS, params=params)

    all_asset_data = resp.json()

    asset_list = [x["id"] for x in all_asset_data]
    asset_owner = [y['foreign_attributes']['XXXXXXX'][0]['XXXXXXXXX'] for y in all_asset_data]

    return asset_list,asset_owner

def update_asset_owner(asset_list,asset_owner):
    count = 0

    for asset_id in asset_list:
        update_url = f"{RUNZERO_BASE_URL}/org/assets/{asset_id}/owners"
        payload = {"ownership_type_id": OWNERSHIP_TYPE_ID,  "owner": asset_owner[count]}  # Update the owner with the new email
        params = {'asset_id': asset_id, "_oid": RUNZERO_ORG_ID}  # Include the organization ID as a parameter

        response = requests.patch(update_url, json=payload, headers=HEADERS, params=params)

        if response.status_code == 200:
            print(f"Successfully updated owner for asset {asset_id} to {asset_owner[count]}")
            count += 1
        else:
            print(f"Failed to update owner for asset {asset_id}. Status code: {response.status_code}")
            print("Response:", response.text)

    return

def main():
    asset_list,asset_owner = get_runzero_assets()
    update_asset_owner(asset_list,asset_owner)

    return

if __name__ == "__main__":
    main()