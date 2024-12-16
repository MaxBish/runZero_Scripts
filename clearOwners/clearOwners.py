import requests

RUNZERO_API_URL = "https://console.runZero.com/api/v1.0"
RUNZERO_ORG_TOKEN = "XXXXXXXXXX"
HEADERS = {"Authorization": f"Bearer {RUNZERO_ORG_TOKEN}"}

search = f"online:t or online:f"

URL = f"{RUNZERO_API_URL}/org/assets/bulk/clearOwners"
json_params = {'search': search}

response = requests.post(url=URL, headers=HEADERS, json=json_params)

if response.status_code == 200:
    print("Owners cleared")
else:
    print("Failed to clear owners")