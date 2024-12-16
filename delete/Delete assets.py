## Delete assets via query

import requests
import json
import os

## runZero export organization token
RUNZERO_ORG_TOKEN = os.environ['RUNZERO_ORG_TOKEN']

RUNZERO_BASE_URL = 'https://console.runZero.com/api/v1.0'
RUNZERO_ORG_ID = os.environ['RUNZERO_ORG_ID']
RUNZERO_SITE_ID = os.environ['RUNZERO_SITE_ID']

## Search query
query = quote('_asset.protocol:tls AND tls.notAfterTS:<30days')

export_url = 'https://console.runzero.com/api/v1.0/org/assets?search={query}'
headers = {"Authorization": f"Bearer {RUNZERO_ORG_TOKEN}"}
params = {"search": f"site:{RUNZERO_SITE_ID}", "fields": "id"}
resp = requests.get(url=export_url, headers=headers, params=params)
asset_list = [x["id"] for x in resp.json()]
if len(asset_list) > 0:
    delete_url = RUNZERO_BASE_URL + "/org/assets/bulk/delete"
    delete = requests.delete(url=delete_url, headers=headers, json={"asset_ids": asset_list}, params={"_oid": RUNZERO_ORG_ID})
    if delete.status_code == 204:
       print("Deleted all assets")