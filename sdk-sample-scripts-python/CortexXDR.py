import requests
import json

from datetime import datetime, timezone
import secrets
import string
import hashlib
import os
from ipaddress import ip_address
from typing import Any, Dict, List

import runzero
from runzero.client import AuthError
from runzero.api import CustomAssets, CustomIntegrationsAdmin, Sites
from runzero.types import (
    CustomAttribute,
    ImportAsset,
    IPv4Address,
    IPv6Address,
    NetworkInterface,
    ImportTask,
)

cortex_api_url = "particular tenant API URL/public_api/v1/"
cortex_api_key = "cortex API key"
cortex_api_key_id = "cortex API key ID"

RUNZERO_CLIENT_ID = "runZero client ID"
RUNZERO_CLIENT_SECRET = "runZero client secret"
RUNZERO_BASE_URL = "https://console.runZero.com/api/v1.0"
RUNZERO_ORG_ID = "runZero ORG ID"
RUNZERO_SITE_NAME = "runZero Site Name"

def do_cortex_api_call(api_call, post_data=None):
    post_data = post_data or {}
    # Generate a 64 bytes random string
    nonce = "".join([secrets.choice(string.ascii_letters + string.digits) for _ in range(64)])

    # Get the current timestamp as milliseconds.
    timestamp = int(datetime.now(timezone.utc).timestamp()) * 1000

    # Generate the auth key:
    auth_key = "%s%s%s" % (cortex_api_key, nonce, timestamp)
  
    # Convert to bytes object
    auth_key = auth_key.encode("utf-8")
  
    # Calculate sha256:
    api_key_hash = hashlib.sha256(auth_key).hexdigest()
  
    # Generate HTTP call headers
    headers = {
        "x-xdr-timestamp": str(timestamp),
        "x-xdr-nonce": nonce,
        "x-xdr-auth-id": str(cortex_api_key_id),
        "Authorization": api_key_hash
    }
    res = requests.post(url=cortex_api_url + api_call,
						headers=headers,
						json=post_data)
 
    return res

  
def get_all_cortex_endpoints():
  cortex_filter = {"request_data": {"search_from": 0, "search_to": 100}}

  all_endpoints = []
  page_size = 100
  while True:
    print("Making Cortex API call...")
    result = json.loads(do_cortex_api_call("endpoints/get_endpoint", cortex_filter.copy()).content)['reply']
        
    fetched_endpoints = result['endpoints']
    all_endpoints.extend(fetched_endpoints)
    if len(fetched_endpoints) < page_size:
        break
        
    cortex_filter['request_data']['search_from'] += page_size
    cortex_filter['request_data']['search_to'] += page_size
    
  print(f"Loaded {len(all_endpoints):,d} endpoints")

  return all_endpoints
  

def build_assets():
  all_endpoints = get_all_cortex_endpoints()
  assets = []
  for endpoint in all_endpoints:
      custom_attrs = {}
      custom_attrs['operational_status'] = endpoint['operational_status']
      custom_attrs['agent_status'] = endpoint['endpoint_status']
      custom_attrs['agent_type'] = endpoint['endpoint_type']
      custom_attrs['last_seen'] = str(int(endpoint['last_seen']/1000))
      custom_attrs['first_seen'] = str(int(endpoint['first_seen']/1000))
      custom_attrs['groups'] = ";".join(endpoint['group_name'])
      custom_attrs['assigned_prevention_policy'] = endpoint['assigned_prevention_policy']
      custom_attrs['assigned_extensions_policy'] = endpoint['assigned_extensions_policy']
      custom_attrs['endpoint_version'] = endpoint['endpoint_version']

      mac_address = None
      if len(endpoint['mac_address']) > 0:
         mac_address = endpoint['mac_address'][0]

      assets.append(ImportAsset(
         id=endpoint['endpoint_id'],
         networkInterfaces=[build_network_interface(ips=endpoint['ip'] + endpoint['ipv6'],mac=mac_address)],
         hostnames=[endpoint['endpoint_name']],
         os_version=endpoint['os_version'],
         os=endpoint['operating_system'],
         customAttributes=custom_attrs
      ))
  return assets

def build_network_interface(ips: List[str], mac: str = None) -> NetworkInterface:
    """
    This function converts a mac and a list of strings in either ipv4 or ipv6 format and creates a NetworkInterface that
    is accepted in the ImportAsset
    """
    ip4s: List[IPv4Address] = []
    ip6s: List[IPv6Address] = []
    for ip in ips[:99]:
        try:
            ip_addr = ip_address(ip)
            if ip_addr.version == 4:
                ip4s.append(ip_addr)
            elif ip_addr.version == 6:
                ip6s.append(ip_addr)
            else:
                continue
        except:
            continue

    if mac is None:
        return NetworkInterface(ipv4Addresses=ip4s, ipv6Addresses=ip6s)
    else:
        return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)

def import_data_to_runzero(assets: List[ImportAsset]):
    """
    The code below gives an example of how to create a custom source and upload valid assets from a CSV to a site using
    the new custom source.
    """
    # create the runzero client
    c = runzero.Client()

    # try to log in using OAuth credentials
    try:
        c.oauth_login(RUNZERO_CLIENT_ID, RUNZERO_CLIENT_SECRET)
    except AuthError as e:
        print(f"login failed: {e}")
        return

    # create the site manager to get our site information
    site_mgr = Sites(c)
    site = site_mgr.get(RUNZERO_ORG_ID, RUNZERO_SITE_NAME)
    if not site:
        print(f"unable to find requested site")
        return

    # get or create the custom source manager and create a new custom source
    custom_source_mgr = CustomIntegrationsAdmin(c)
    my_asset_source = custom_source_mgr.get(name="cortex-xdr")
    if my_asset_source:
        source_id = my_asset_source.id
    else:
        my_asset_source = custom_source_mgr.create(name="cortex-xdr")
        source_id = my_asset_source.id

    # create the import manager to upload custom assets
    import_mgr = CustomAssets(c)
    import_task = import_mgr.upload_assets(
        org_id=RUNZERO_ORG_ID,
        site_id=site.id,
        custom_integration_id=source_id,
        assets=assets,
        task_info=ImportTask(name="Cortex XDR Sync"),
    )

    if import_task:
        print(
            f"task created! view status here: https://console.runzero.com/tasks?task={import_task.id}"
        )



if __name__ == "__main__":
    cortex_endpoints = build_assets()
    import_data_to_runzero(cortex_endpoints)
