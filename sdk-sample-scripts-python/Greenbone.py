## Greenbone

## importing dependencies
from ipaddress import ip_address
import sys
import requests

import json
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

# Configuration - Replace with your actual credentials
GVM_API_URL = 'https://your-greenbone-instance.com/api'
GVM_USERNAME = 'your_username'
GVM_PASSWORD = 'your_password'
RUNZERO_API_KEY = 'your_runzero_api_key'
RUNZERO_URL = 'https://api.runzero.com'  # URL for RunZero's API
RUNZERO_ORG_ID = 'XXXXX'

# Helper function to authenticate with Greenbone API
def authenticate_gvm():
    # Perform authentication (may vary depending on Greenbone's specific API)
    auth_url = f"{GVM_API_URL}/auth"
    payload = {'username': GVM_USERNAME, 'password': GVM_PASSWORD}
    response = requests.post(auth_url, json=payload)
    response.raise_for_status()
    return response.json()['access_token']

# Helper function to fetch assets from Greenbone
def fetch_assets_from_gvm(auth_token):
    # This is a simplified query. Modify based on Greenbone's API endpoints
    assets_url = f"{GVM_API_URL}/assets"
    headers = {'Authorization': f'Bearer {auth_token}'}
    response = requests.get(assets_url, headers=headers)
    response.raise_for_status()
    return response.json()

def build_assets(assets_data):

  assets = []
  for endpoint in assets_data:
      custom_attrs = {}
      custom_attrs['os_version'] = endpoint['os_version']
      custom_attrs['os_name'] = endpoint['os_name']
      custom_attrs['os_family'] = endpoint['os_family']
      custom_attrs['agent_version'] = endpoint['agent_version']
      custom_attrs['compliant'] = str(endpoint['compliant'])
      custom_attrs['last_logged_in_user'] = endpoint['last_logged_in_user']
      custom_attrs['serial_number'] = endpoint['serial_number']
      custom_attrs['agent_status'] = endpoint['status']['agent_status']


      mac_address = None
      if len(endpoint['detail']['NICS'][0]['MAC']) > 0:
         mac_address = endpoint['detail']['NICS'][0]['MAC']

      ## handle IPs
      ips = []
      ips.append(endpoint['ip_addrs'])
      ips.append(endpoint['ip_addrs_private'])

      assets.append(ImportAsset(
         id=endpoint['id'],
         networkInterfaces=[build_network_interface(ips=ips,mac=mac_address)],
         hostnames=[endpoint['name']],
         os_version=endpoint['os_version'],
         customAttributes=custom_attrs
      ))
  return assets

def build_network_interface(ips: list[str], mac: str = None) -> NetworkInterface:
    """
    This function converts a mac and a list of strings in either ipv4 or ipv6 format and creates a NetworkInterface that
    is accepted in the ImportAsset
    """
    ip4s: list[IPv4Address] = []
    ip6s: list[IPv6Address] = []
    for ip in ips[:99]:
            ip_addr = ip_address(ip[0])
            if ip_addr.version == 4:
                ip4s.append(ip_addr)
            elif ip_addr.version == 6:
                ip6s.append(ip_addr)
            else:
                continue

    if mac is None:
        return NetworkInterface(ipv4Addresses=ip4s, ipv6Addresses=ip6s)
    else:
        return NetworkInterface(macAddress=mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)


def import_data_to_runzero(assets: list[ImportAsset]):
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
    my_asset_source = custom_source_mgr.get(name="Greenbone")
    if my_asset_source:
        source_id = my_asset_source.id
    else:
        my_asset_source = custom_source_mgr.create(name="Greenbone")
        source_id = my_asset_source.id

    # create the import manager to upload custom assets
    import_mgr = CustomAssets(c)
    import_task = import_mgr.upload_assets(
        org_id=RUNZERO_ORG_ID,
        site_id=site.id,
        custom_integration_id=source_id,
        assets=assets,
        task_info=ImportTask(name="Greenbone Sync"),
    )

    if import_task:
        print(
            f"task created! view status here: https://console.runzero.com/tasks?task={import_task.id}"
        )

# Main function to pull data and send to RunZero
def main():
    try:
        # Authenticate and get Greenbone assets & vulnerabilities
        auth_token = authenticate_gvm()
        
        assets_data = fetch_assets_from_gvm(auth_token)

        assets = build_assets(assets_data)

        import_data_to_runzero(assets)

    
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()