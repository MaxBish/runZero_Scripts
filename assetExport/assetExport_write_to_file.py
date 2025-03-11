import requests
import json
import os
import csv

RUNZERO_URL = "https://IP:443/api/v1.0"

RUNZERO_API_KEY = "YOUR_API_KEY"
headers = {
    "Authorization": f"Bearer {RUNZERO_API_KEY}"
}

params = {"search": "has:@crowdstrike.dev.serialNumber"}

def main():
   # Create a CSV file to store the results
    file_path = os.path.join(os.getcwd(), 'serial_number_output.csv')

    resp = requests.get(f"{RUNZERO_URL}/org/assets", headers=headers, params=params)

    batchsize = 500
    if len(resp.json()) > 0 and resp.status_code == 200:
        for i in range(0, len(resp.json()), batchsize):
            batch = resp.json()[i:i+batchsize]
            f = open("export.csv", "w")
            f.truncate(0)
            for a in batch:
                json.dump(a, f)
                f.write("\n")
            f.close()
    else:
        print(f"No assets found - status code from runZero API: {resp.status_code}")

if __name__ == '__main__':
    main()  