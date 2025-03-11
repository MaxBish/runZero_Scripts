import requests
import json
import os
import csv

# API Configuration
RUNZERO_URL = "https://console.runZero.com/api/v1.0"
RUNZERO_API_KEY = "XXXXXXXXXXXXXXXXXXXXXXXXXXX"  # Replace with your actual API key

headers = {
    "Authorization": f"Bearer {RUNZERO_API_KEY}"
}

params = {
    "search": "alive:t and type:=server",  
    "fields": ["type,os,hw,addresses,macs,names,tags,foreign_attributes"]
}

def fetch_assets():
    """Fetch assets from runZero API."""
    try:
        resp = requests.get(f"{RUNZERO_URL}/org/assets", headers=headers, params=params)
        resp.raise_for_status()  # Raise an exception for HTTP errors (4xx, 5xx)
        return resp.json()  # Return JSON data if successful
    except requests.exceptions.RequestException as e:
        print(f"Error fetching data: {e}")
        return []

def save_to_csv(data):
    """Save asset data to a CSV file."""
    file_path = os.path.join(os.getcwd(), 'export.csv')
    fieldnames = ["type", "os", "hw", "addresses", "macs", "names", "tags", "foreign_attributes"]

    # Open file in write mode and set up CSV writer
    with open(file_path, "w", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()  # Write column headers

        for asset in data:
            writer.writerow({
                "type": asset.get("type", ""),
                "os": asset.get("os", ""),
                "hw": asset.get("hw", ""),
                "addresses": ", ".join(asset.get("addresses", [])),
                "macs": ", ".join(asset.get("macs", [])),
                "names": ", ".join(asset.get("names", [])),
                "tags": ", ".join(asset.get("tags", [])),
                "foreign_attributes": json.dumps(asset.get("foreign_attributes", {}))
            })
    print(f"Data saved to {file_path}")

def main():
    """Main execution function."""
    data = fetch_assets()
    
    if data:
        save_to_csv(data)
    else:
        print("No assets found or failed to retrieve data.")

if __name__ == '__main__':
    main()
