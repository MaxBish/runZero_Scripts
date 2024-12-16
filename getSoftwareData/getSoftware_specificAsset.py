import requests
import os
import csv

# Replace with your RunZero API key
# 
RUNZERO_ORG_TOKEN = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'

# Base URL for RunZero API
base_url = 'https://console.runzero.com/api/v1.0'

# Function to get the list of assets
def get_assets(api_key):
    query = 'tag:"FalconGroupingTags/swift"'
    url = f'{base_url}/export/org/assets.json'
    headers = {'Authorization': f'Bearer {api_key}'}

    response = requests.get(url, params={'search': query, 'fields': ['id,addresses']}, headers=headers)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f'Error fetching assets: {response.status_code} - {response.text}')
        return []

# Function to get software of a particular asset
def get_software(api_key):
    url = f'{base_url}/export/org/software.json'
    headers = {
        'Authorization': f'Bearer {api_key}'
    }
    
    response = requests.get(url, params={'fields': ['software_asset_id,software_product,software_version']}, headers=headers)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f'Error fetching software: {response.status_code} - {response.text}')
        return []

# Main logic to get assets and software
def main():
    # Fetch the list of assets
    assets = get_assets(RUNZERO_ORG_TOKEN)

    # Fetch the list of software
    software_list = get_software(RUNZERO_ORG_TOKEN)

    # Create a CSV file to store the results
    file_path = os.path.join(os.getcwd(), 'software_output.csv')
    data = []
    
    if assets:
        for asset in assets:
            asset_id = asset['id'] # Extract asset ID
            asset_address = asset['addresses'][0]  # Extract asset name
            print(f"Fetching software for Asset: {asset_address}")

            if software_list:
                for software in software_list:
                    if software['software_asset_id'] == asset_id:  # Add the asset ID to each software entry
                        print(f"Software installed on Asset {asset_address}:")

                        print(f"  - {software['software_product']} (Version: {software['software_version']})")

                        row = [asset_address, software['software_product'], software['software_version']]

                        data.append(row)
    else:
        print("No assets found.")

    with open(file_path, 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['Asset', 'Software', 'Version'])
        writer.writerows(data)

if __name__ == '__main__':
    main()