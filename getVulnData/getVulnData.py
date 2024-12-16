import requests
import os
import csv

# Replace with your RunZero API key 
RUNZERO_ORG_TOKEN = 'XXXXXXXXXXXXXXXXXX'

# Base URL for RunZero API
base_url = 'https://console.runzero.com/api/v1.0'

# Function to get the list of assets
def get_assets(api_key):

    ## enter your service provider account ID
    query = '@crowdstrike.dev.serviceProviderAccountID:"XXXXXXXXXXXXXXX"'


    url = f'{base_url}/export/org/assets.json'
    headers = {'Authorization': f'Bearer {api_key}'}

    response = requests.get(url, params={'search': query, 'fields': ['id,addresses']}, headers=headers)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f'Error fetching assets: {response.status_code} - {response.text}')
        return []

# Function to get vulnerabilities of a particular asset
def get_vulnerabilities(api_key):
    """
    Fetches the list of vulnerabilities in the organization.

    :param api_key: The RunZero API key.
    :return: A list of vulnerabilities.
    """
    url = f'{base_url}/export/org/vulnerabilities.json'
    headers = {
        'Authorization': f'Bearer {api_key}'
    }
    
    response = requests.get(url, params={'fields': ['vulnerability_asset_id,vulnerability_name,vulnerability_risk']}, headers=headers)
    
    if response.status_code == 200:
        # Return the JSON response
        return response.json()
    else:
        # Print an error message and return an empty list
        print(f'Error fetching vulnerabilites: {response.status_code} - {response.text}')
        return []

# Main logic to get assets and vulnerabilities
def main():
    # Fetch the list of assets
    assets = get_assets(RUNZERO_ORG_TOKEN)

    # Fetch the list of vulnerabilities
    vulnerability_list = get_vulnerabilities(RUNZERO_ORG_TOKEN)

    # Create a CSV file to store the results
    file_path = os.path.join(os.getcwd(), 'vulnerabilities_output.csv')
    data = []
    
    if assets:
        for asset in assets:
            asset_id = asset['id'] # Extract asset ID
            asset_address = asset['addresses'][0]  # Extract asset address
            print(f"Fetching vulnerabilities for Asset: {asset_address}")

            if vulnerability_list:
                for vuln in vulnerability_list:
                    if vuln['vulnerability_asset_id'] == asset_id:  # Add the asset ID to each vulnerability entry
                        print(f"Vulnerability on Asset {asset_address}:")

                        print(f"  - {vuln['vulnerability_name']} (Risk: {vuln['vulnerability_risk']})")

                        row = [asset_address, vuln['vulnerability_name'], vuln['vulnerability_risk']]

                        data.append(row)
    else:
        print("No assets found.")

    with open(file_path, 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['Asset', 'Vulnerability', 'Risk'])
        writer.writerows(data)

if __name__ == '__main__':
    main()