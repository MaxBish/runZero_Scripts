import requests
import os
import csv

# Replace with your RunZero API key
# 
RUNZERO_ORG_TOKEN = 'XXXXXXXXXXXXXX'

# Base URL for RunZero API
base_url = 'https://console.runzero.com/api/v1.0'

# Function to get the list of assets
def get_assets(api_key):
    query = 'alive:t and type:=server'
    url = f'{base_url}/export/org/assets.json'
    headers = {'Authorization': f'Bearer {api_key}'}

    response = requests.get(url, params={'search': query, 'fields': ['id,addresses,names']}, headers=headers)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f'Error fetching assets: {response.status_code} - {response.text}')
        return []

# Function to get software of a particular asset
def get_software(api_key, asset_id):
    url = f'{base_url}/export/org/software.json'
    headers = {
        'Authorization': f'Bearer {api_key}'
    }
    params = {"search": f"asset_id:{asset_id}", "fields": ["software_vendor,software_product,software_version"]}
    
    response = requests.get(url, headers=headers, params=params)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f'Error fetching software: {response.status_code} - {response.text}')
        return []

# Main logic to get assets and software
def main():
    # Fetch the list of assets
    assets = get_assets(RUNZERO_ORG_TOKEN)

    for asset in assets:
        count = 0
        asset_id = asset['id']
        if asset_id:
            assets[count]['software'] = get_software(RUNZERO_ORG_TOKEN, asset_id)

    # Create a CSV file to store the results
    file_path = os.path.join(os.getcwd(), 'software_output.csv')
    data = []
    
    if assets:
        for asset in assets:
            count = 0
            asset_id = asset['id'] # Extract asset ID
            asset_address = asset['addresses'][0]
            asset_name = asset['names']  # Extract asset name
            print(f"Fetching software for Asset: {asset_address}")

            for software in asset['software']:
                print(f"Software installed on Asset {asset_address} ({asset_name}):")

                print(f"  - {software['software_product']} (Version: {software['software_version']})")

                row = [asset_address, asset_name,software['software_product'], software['software_version']]

                data.append(row)
    else:
        print("No assets found.")

    with open(file_path, 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['Asset IP', 'Asset Name', 'Software', 'Version'])
        writer.writerows(data)

if __name__ == '__main__':
    main()