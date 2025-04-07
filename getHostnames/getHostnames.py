import requests
import csv

# Config
RUNZERO_API_TOKEN = "your_runzero_api_token"
RUNZERO_API_URL = "https://console.runzero.com/api/v1.0"

# Input/Output files
INPUT_FILE = "ips.txt"
OUTPUT_FILE = "ips_output.csv"

# Headers for runZero API
HEADERS = {
    "Authorization": f"Bearer {RUNZERO_API_TOKEN}",
    "Content-Type": "application/json"
}

def get_assets_by_ip(ip):
    """Query runZero for assets matching a specific IP address."""
    params = {"search": "address:" + ip, "fields": "addresses,names"}
    response = requests.get(
        f"{RUNZERO_API_URL}/org/assets",
        headers=HEADERS,
        params=params
    )
    response.raise_for_status()
    return response.json()

def main():
    results = []

    with open(INPUT_FILE, "r") as f:
        ips = [line.strip() for line in f if line.strip()]

    for ip in ips:
        print(f"Looking up IP: {ip}")
        assets = get_assets_by_ip(ip)
        for asset in assets:
            results.append({
                "addresses": asset["addresses"],
                "hostname": asset["names"],
            })

    with open(OUTPUT_FILE, "w", newline="") as csvfile:
        fieldnames = ["ips", "hostname"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"Export complete: {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
