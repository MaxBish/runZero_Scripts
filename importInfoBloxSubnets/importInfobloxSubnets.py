## Import InfoBlox subnets and tags into runZero

import requests
import json
from requests.auth import HTTPBasicAuth

# Initialize the subnets dictionary
subnets = {
    "name": "",
    "description": "",
    "scope": "",
    "excludes": "",
    "subnets": {}
}

# Function to pull IPAM JSON leveraging basic authentication
def get_ipam(user, pwd):
    """
    Pull IPAM JSON leveraging basic authentication.

    Args:
        user (str): InfoBlox username.
        pwd (str): InfoBlox password.

    Returns:
        list: List of IPAM data.
    """
    # IPAM API URL
    ipam_base_url = (
        "hxxps[:]//<UPDATE_ME>/wapi/<UPDATE_ME>/network?"
        "_max_results=10000&_return_fields=comment,network,extattrs,members,utilization,"
        "total_hosts,unmanaged_count,discovered_vlan_id,discovered_vlan_name,discovered_vrf_name"
        "&_return_type=json"
    )

    try:
        # Make request to IPAM API
        resp = requests.get(ipam_base_url, auth=HTTPBasicAuth(user, pwd))
        resp.raise_for_status()  # Raise error if response is unsuccessful
        return resp.json()
    except requests.exceptions.RequestException as e:
        # Handle errors encountered while pulling IPAM data
        print(f"Error encountered while pulling IPAM data: {e}")
        return None



def extract_tag(data, keys, fallback="MISSING"):
    """
    Safely extract nested values from dictionaries.

    Given a list of keys, traverse the dictionary and return the value at the
    end of the key chain. If any key is missing, return the specified fallback
    value.

    Args:
        data (dict): Dictionary to extract value from.
        keys (list): List of keys to traverse.
        fallback (str): Value to return if any key is missing.

    Returns:
        str: Extracted value or fallback if any key is missing.
    """
    for key in keys:
        data = data.get(key)
        if data is None:
            continue
        return data
    return fallback

def generate_body(json_array):
    """
    Processes IPAM JSON and structures it for runZero.

    This function iterates over the list of IPAM data and extracts the
    network range and tags for each item. Tags are extracted from the
    extattrs dictionary in the IPAM data. The function then structures
    the data into the expected format for runZero and returns the
    formatted data as a JSON string.

    Args:
        json_array (list): List of IPAM data.

    Returns:
        str: Formatted data as a JSON string.
    """

    for item in json_array:
        network_range = item.get("network", "UNKNOWN")
        tags = {
            "DESCRIPTION": extract_tag(item, ["comment"]),
            "BUILDING": extract_tag(item, ["extattrs", "Building", "value"]),
            # If the VRF value is not present in the extattrs, use the discovered_vrf_name
            "VRF": extract_tag(item, ["extattrs", "VRF", "value"], item.get("discovered_vrf_name", "MISSING")),
            # If the VLAN value is not present in the extattrs, use the discovered_vlan_id
            "VLAN": extract_tag(item, ["extattrs", "VLAN", "value"], item.get("discovered_vlan_id", "MISSING")),
        }

        subnets["subnets"][network_range] = {"tags": tags}

    return json.dumps(subnets, indent=4)

# Send data to RunZero API
def send_data(subnets_body, site_name, site_description, site_exclusions, site_scope, site_id, authorization_token, runzero_org_name):
    """Sends subnet data to the runZero API.

    This function takes the formatted subnet data and sends it to the runZero API
    using a PATCH request. The function returns the response body as a JSON
    object.

    Args:
        subnets_body (dict): Formatted subnet data.
        site_name (str): Name of the site.
        site_description (str): Description of the site.
        site_exclusions (str): Exclusions for the site.
        site_scope (str): Scope of the site.
        site_id (str): ID of the site.
        authorization_token (str): runZero API token.
        runzero_org_name (str): Name of the runZero organization.

    Returns:
        dict: Response body as a JSON object.
    """

    # Update subnets dictionary with site-specific data
    subnets_body.update({
        "name": site_name,
        "description": site_description,
        "excludes": site_exclusions,
        "scope": site_scope
    })

    api_url = f"https://console.runzero.com/api/v1.0/org/sites/{site_id}"
    headers = {
        "Authorization": f"Bearer {authorization_token}",
        "site_id": site_id
    }

    try:
        response = requests.patch(api_url, json=subnets_body, headers=headers)
        response.raise_for_status()
        print(f"Data sent successfully to site '{site_name}' in organization '{runzero_org_name}'")
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error sending data to RunZero: {e}")
        return None

def main():
    """
    Main function to pull IPAM data and send it to runZero.

    This function performs the following steps:
    1. Pulls IPAM data from the IPAM server.
    2. Generates a formatted payload for runZero.
    3. Sends the payload to the runZero API.
    """

    # User configuration - **Replace these with actual values**
    user = "XXXXXXX"  # InfoBlox username
    pwd = "YYYYYYYY"  # InfoBlox password
    site_id = "ZZZ"  # runZero site ID
    authorization_token = "AAA"  # runZero API token
    runzero_org_name = "BBB"  # runZero organization name
    site_name = "XXX"  # Name of the site inside the organization
    site_description = "YYY"  # Site description
    site_scope = ""  # Site scope (modify if needed)
    site_exclusions = "10.0.0.0/24"  # Exclusions (update as needed)

    # Pull IPAM data
    ipam_data = get_ipam(user, pwd)

    if not ipam_data:
        print("No data retrieved from IPAM. Exiting...")
        return

    # Generate formatted payload for runZero
    payload = json.loads(generate_body(ipam_data))

    # Send data to runZero
    send_data(payload, site_name, site_description, site_exclusions, site_scope, site_id, authorization_token, runzero_org_name)

if __name__ == "__main__":
    main()