import requests
import csv

# ========== Configuration ==========
RUNZERO_API_TOKEN = "RUNZERO_ORG_TOKEN"  # Replace with your runZero Org Token
RUNZERO_API_URL = "https://console.runzero.com/api/v1.0"
INPUT_FILE = "ips.txt"
OUTPUT_FILE = "ips_output.csv"

HEADERS = {
    "Authorization": f"Bearer {RUNZERO_API_TOKEN}",
    "Content-Type": "application/json"
}

# ========== API Query ==========
def get_assets_by_ip(ip):
    """Query runZero for assets matching a specific IP address."""
    params = {"search": f"address:{ip}", "fields": "addresses,names"}
    response = requests.get(
        f"{RUNZERO_API_URL}/org/assets",
        headers=HEADERS,
        params=params
    )
    response.raise_for_status()
    return response.json()

# ========== Main Logic ==========
def main():
    results = []

    with open(INPUT_FILE, "r") as f:
        ips = [line.strip() for line in f if line.strip()]

    for ip in ips:
        print(f"Looking up IP: {ip}")
        try:
            assets = get_assets_by_ip(ip)
            if assets:
                for asset in assets:
                    results.append({
                        "ip": ", ".join(asset["addresses"]),
                        "hostname": ", ".join(asset["names"]),
                    })
            else:
                results.append({
                    "ip": ip,
                    "hostname": "No asset found"
                })
        except requests.exceptions.HTTPError:
            results.append({
                "ip": ip,
                "hostname": "API Error"
            })

    # Write results to CSV
    with open(OUTPUT_FILE, "w", newline="") as csvfile:
        fieldnames = ["ip", "hostname"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"Export complete: {OUTPUT_FILE}")

# ========== Entry Point ==========
if __name__ == "__main__":
    main()
