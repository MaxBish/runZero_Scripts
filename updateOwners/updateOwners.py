import requests
import json
import csv
import os

RUNZERO_BASE_URL = "https://console.runZero.com/api/v1.0"
RUNZERO_ORG_ID = "runZero ORG ID"
RUNZERO_ORG_TOKEN = os.environ["RUNZERO_ORG_TOKEN"]
HEADERS = {"Authorization": f"Bearer {RUNZERO_ORG_TOKEN}"}
OWNERSHIP_TYPE_ID = '00000000-0000-0000-0000-000000000000'

def get_runzero_assets():

    ## Search query
    query = 'ip:XXXX.XXX.XXX.XXX'    
    url = f"{RUNZERO_BASE_URL}/org/assets.json"

    params = {"search": query, "fields": "id"}

    resp = requests.get(url=url, headers=HEADERS, params=params)

    asset_list = [x["id"] for x in resp.json()]

    return asset_list

def update_asset_owner(asset_list, new_owner_email):
    for asset_id in asset_list:
        update_url = f"{RUNZERO_BASE_URL}/org/assets/{asset_id}/owners"
        payload = {"ownership_type_id": OWNERSHIP_TYPE_ID,  "owner": [new_owner_email]}  # Update the owner with the new email
        params = {"_oid": RUNZERO_ORG_ID}  # Include the organization ID as a parameter

        response = requests.patch(update_url, json=payload, headers=HEADERS, params=params)

        if response.status_code == 200:
            print(f"Successfully updated owner for asset {asset_id} to {new_owner_email}")
        else:
            print(f"Failed to update owner for asset {asset_id}. Status code: {response.status_code}")
            print("Response:", response.text)

    return

def main():
    asset_list = get_runzero_assets()
    new_owner_email = "new owner email" ## or read .csv or have a list of users/emails to update
    update_asset_owner(asset_list, new_owner_email)

    return

if __name__ == "__main__":
    main()