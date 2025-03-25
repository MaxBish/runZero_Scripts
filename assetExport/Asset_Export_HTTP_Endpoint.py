import json
import requests

HTTP_ENDPOINT = "<UPDATE_ME>"
BASE_URL = "https://console.runZero.com/api/v1.0"
SEARCH = "id:XXXXXXXXXXXX"


def get_assets(headers):
    """Fetch assets from runZero API."""
    assets = []
    url = f"{BASE_URL}/org/assets"
    params = {"search": SEARCH}
    response = requests.get(url, headers=headers, params=params)

    if response.status_code == 200:
        assets_json = response.json()
        if assets_json:
            print(f"Got {len(assets_json)} assets")
            return assets_json
        else:
            print("runZero did not return any assets")
    else:
        print(f"runZero API request failed - status code {response.status_code}")

    return None

def sync_to_http_endpoint(assets):
    """Send assets to an HTTP endpoint in batches."""
    print(f"Sending {len(assets)} assets to HTTP endpoint")
    batch_size = 500

    if assets:
        for i in range(0, len(assets), batch_size):
            batch = assets[i:i + batch_size]
            payload = "\n".join(json.dumps(a) for a in batch)
            response = requests.post(HTTP_ENDPOINT, data=payload.encode())

            if response.status_code != 200:
                print(f"Failed to send batch to HTTP endpoint - status code {response.status_code}")
    else:
        print("No assets found")

def get_software(headers, asset_id):
    url = f"{BASE_URL}/export/org/software.json"

    params = {"search": f"asset_id:{asset_id}", "fields": ["software_vendor,software_product,software_version"]}

    response = requests.get(url, headers=headers, params=params)

    if response.status_code == 200:
        return response.json()
    else:
        print(f"Failed to fetch software for asset {asset_id} - status code {response.status_code}")
        return None
    

def get_vulnerabilities(headers, asset_id):
    url = f"{BASE_URL}/export/org/vulnerabilities.json"

    params = {"search": f"asset_id:{asset_id}", "fields": ['vulnerability_name,vulnerability_cve,vulnerability_risk,vulnerability_exploitable']}

    response = requests.get(url, headers=headers, params=params)

    if response.status_code == 200:
        return response.json()
    else:
        print(f"Failed to fetch vulnerabilities for asset {asset_id} - status code {response.status_code}")
        return None


def main():
    """Main function to fetch and sync assets."""
    headers = {"Authorization": f"Bearer <UPDATE_ME>"}
    assets = get_assets(headers=headers)

    if assets:
        for asset in assets:
            count = 0
            id = asset["id"]
            name = asset["names"]
            asset_address = asset["addresses"][0]

            print(f"Fetching software data for asset: {asset_address}")

            software_list = get_software(headers=headers, asset_id=id)

            if software_list:
                assets[count]["software"] = software_list
            else:
                print(f"No software data found for asset {asset_address}")

            print(f"Fetching vulnerability data for asset: {asset_address}")

            vulnerability_list = get_vulnerabilities(headers=headers, asset_id=id)

            if vulnerability_list:
                assets[count]["vulnerabilities"] = vulnerability_list
            else:
                print(f"No vulnerability data found for asset {asset_address}")

            count = count + 1
        
        sync_to_http_endpoint(assets)


if __name__ == "__main__":
    main()