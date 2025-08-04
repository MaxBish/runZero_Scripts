import requests
import csv
import json

# --- CONFIGURATION ---
# Replace 'YOUR_API_KEY' with your actual runZero API key.
# This key should be kept secure and not shared.
API_KEY = 'YOUR_API_KEY' 

# The base URL for the runZero API's asset export endpoint.
API_BASE_URL = f'https://console.runzero.com/api/v1.0/export/org/assets'

# The name of the output CSV file.
OUTPUT_FILENAME = 'firmware_versions.csv'

# --- API REQUEST SETUP ---
headers = {
    'Authorization': f'Bearer {API_KEY}',
    'Accept': 'application/json'
}

# The list of device types you want to search for.
DEVICE_TYPES = [
    'Switch',
    'IP Camera',
    'Network Appliance',
    'WAP',
    'Smart TV',
    'IP Phone',
    'Router',
    'Network Management',
    'Video Conferencing',
    'IoT',
    'NAS'
]

# Construct a search query to filter for these device types and for assets with CPE data.
# The query will be: 'has:fp.os.cpe AND (type:"Switch" OR type:"IP Camera" OR ...)'
search_query_parts = [f'type:"{device_type}"' for device_type in DEVICE_TYPES]
device_type_query = ' OR '.join(search_query_parts)
full_search_query = f'has:fp.os.cpe AND ({device_type_query})'

# Set the new, more specific search parameter.
params = {
    'search': full_search_query
}

# --- SCRIPT LOGIC ---
def get_assets_with_firmware():
    """
    Fetches assets from the runZero API that have firmware information and match the specified device types.
    
    Returns:
        A list of dictionaries, where each dictionary represents an asset.
        Returns None if the API request fails.
    """
    print(f"Fetching asset data from runZero with search query: '{params['search']}'")
    try:
        response = requests.get(API_BASE_URL, headers=headers, params=params)
        response.raise_for_status()  # This will raise an HTTPError if the response was an error.
        
        assets = response.json()
        print(f"Successfully fetched {len(assets)} assets.")
        return assets
        
    except requests.exceptions.RequestException as e:
        print(f"Error fetching data from the API: {e}")
        return None

def write_to_csv(assets):
    """
    Writes asset data to a CSV file.
    
    Args:
        assets: A list of asset dictionaries from the runZero API.
    """
    if not assets:
        print("No assets to write to the CSV file.")
        return
        
    print(f"Writing data to {OUTPUT_FILENAME}...")
    with open(OUTPUT_FILENAME, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['hostname', 'ip_address', 'firmware_cpe', 'firmware_version']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        writer.writeheader()
        
        for asset in assets:
            hostname = asset.get('hostname', 'N/A')
            
            # Use the first IP address from the 'addresses' list.
            addresses = asset.get('addresses', [])
            ip_address = addresses[0] if addresses else 'N/A'
            
            # Access the nested 'fp.os.cpe' list using chained .get() with default values.
            cpe_list = asset.get('fp', {}).get('os', {}).get('cpe', [])
            
            # Grab the first CPE string if the list is not empty.
            firmware_cpe = cpe_list[0] if cpe_list else 'N/A'
            
            # Extract the version from the CPE string.
            firmware_version = firmware_cpe.split(':')[4] if firmware_cpe != 'N/A' and len(firmware_cpe.split(':')) > 4 else 'N/A'
            
            writer.writerow({
                'hostname': hostname,
                'ip_address': ip_address,
                'firmware_cpe': firmware_cpe,
                'firmware_version': firmware_version
            })

    print(f"Successfully wrote data to {OUTPUT_FILENAME}")

# --- MAIN EXECUTION ---
if __name__ == "__main__":
    asset_list = get_assets_with_firmware()
    if asset_list:
        write_to_csv(asset_list)