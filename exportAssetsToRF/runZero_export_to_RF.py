## Exporting data from runZero to Recorded Future

import requests
import json

# Configuration
RUNZERO_API_KEY = "your_runzero_api_key"
RECORDED_FUTURE_API_KEY = "your_recorded_future_api_key"
RECORDED_FUTURE_LIST_ID = "your_list_id"

# API Endpoints
RUNZERO_API_BASE = "https://console.runzero.com/api/v1.0"
RECORDED_FUTURE_API_BASE = "https://api.recordedfuture.com/v2"
ENTITY_MATCH_API_URL = f"{RECORDED_FUTURE_API_BASE}/entity-match"
LIST_API_URL = f"{RECORDED_FUTURE_API_BASE}/list/{RECORDED_FUTURE_LIST_ID}/entity/add"
ENTITY_UPDATE_URL = f"{RECORDED_FUTURE_API_BASE}/entity"

# Headers
RUNZERO_HEADERS = {"Authorization": f"Bearer {RUNZERO_API_KEY}"}
RF_HEADERS = {
    "X-RFToken": RECORDED_FUTURE_API_KEY,
    "Content-Type": "application/json"
}

# Function to query runZero assets
def query_runzero_assets(query):
    """
    Queries runZero for assets based on a given query.

    :param query: The query to run against the runZero API.
    :return: A list of assets that match the query.
    """
    headers = {"Authorization": f"Bearer {RUNZERO_API_KEY}"}
    params = {"search": query}

    # Make the API call
    response = requests.get(f"{RUNZERO_API_BASE}/export/org/assets.json", headers=headers, params=params)

    # Handle errors
    if response.status_code == 200:
        return response.json()
    else:
        print("Error querying runZero assets:", response.text)
        return []

# Function to get software for a specific asset
def get_asset_software(asset_id):
    """
    Fetches the software information for a specific asset.

    :param asset_id: The ID of the asset to fetch software information for.
    :return: A list of software details for the asset.
    """
    software = []
    headers = {"Authorization": f"Bearer {RUNZERO_API_KEY}"}
    params = {"search": f"asset_id:{asset_id}"}

    # Request software data from the runZero API
    response = requests.get(f"{RUNZERO_API_BASE}/export/org/software.json", headers=headers, params=params)
    
    # Parse the response if the request was successful
    software_data = response.json() if response.status_code == 200 else []

    if software_data:
        # Iterate over each software entry and extract product and version
        for entry in software_data:
            software_product = entry['software_product']
            software_version = entry['software_version']
            # Concatenate product name and version, then add to the list
            software.append(f"{software_product} {software_version}")
    else:
        return []

    return software

# Function to get vulnerabilities for a specific asset
def get_asset_vulnerabilities(asset_id):
    """
    Fetches vulnerability information for a specific asset.

    :param asset_id: The ID of the asset to fetch vulnerability information for.
    :return: Three lists containing vulnerability names, risks, and CVEs.
    """
    # Initialize lists to store vulnerability details
    vulnerabilities_names = []
    vulnerabilities_risks = []
    vulnerabilities_cves = []

    # Set up headers and parameters for the API request
    headers = {"Authorization": f"Bearer {RUNZERO_API_KEY}"}
    params = {"search": f"asset_id:{asset_id}"}

    # Make the API request to fetch vulnerabilities
    response = requests.get(f"{RUNZERO_API_BASE}/export/org/vulnerabilities.json", headers=headers, params=params)
    # Parse the JSON response if the request was successful, else return empty lists
    vulnerability_data = response.json() if response.status_code == 200 else []

    # Process each vulnerability entry if data is available
    if vulnerability_data:
        for vulnerability in vulnerability_data:
            # Extract details for each vulnerability
            vulnerability_name = vulnerability['vulnerability_name']
            vulnerability_risk = vulnerability['vulnerability_risk']
            vulnerability_cve = vulnerability['vulnerability_cve']
            # Append the details to respective lists
            vulnerabilities_names.append(vulnerability_name)
            vulnerabilities_risks.append(vulnerability_risk)
            vulnerabilities_cves.append(vulnerability_cve)
    else:
        # Return empty lists if no data is available
        return [], [], []

    # Return the lists containing vulnerability details
    return vulnerabilities_names, vulnerabilities_risks, vulnerabilities_cves

# Function to enrich assets with software and vulnerability data
def enrich_assets_with_details(assets):
    """
    Enriches a list of assets with software and vulnerability information.

    :param assets: The list of assets to enrich.
    :return: The enriched list of assets.
    """
    for asset in assets:
        asset_id = asset['id']
        if asset_id:
            # Get software details for the asset
            asset['software'] = get_asset_software(asset_id)
            # Get vulnerability details for the asset
            asset['vulnerabilities_name'],asset['vulnerabilities_risk'],asset['vulnerabilities_cve'] = get_asset_vulnerabilities(asset_id)
    return assets

# Function to match assets with Recorded Future
def match_entity_in_rf(asset_names, asset_type):
    """
    Matches a list of asset names with a single asset type against Recorded Future to find a matching entity.

    :param asset_names: The list of asset names to match.
    :param asset_type: The type of assets to match, e.g. "host" or "service".
    :return: The ID of the matched entity, or None if no match is found.
    """
    payload = {"name": asset_names, "type": [asset_type]}
    response = requests.post(ENTITY_MATCH_API_URL, headers=RF_HEADERS, json=payload)
    
    # Check if the response was successful
    if response.status_code == 200:
        # Get the matches from the response
        matches = response.json()
        # Return the ID of the first match, or None if there are no matches
        return matches[0]["id"] if matches else None
    else:
        # Print an error message if the response was not successful
        print(f"Error matching entity: {response.text}")
        # Return None to indicate no match was found
        return None

# Function to update an existing entity in Recorded Future with software and vulnerabilities
def update_entity_in_rf(entity_id, asset):
    """
    Updates an existing entity in Recorded Future with software and vulnerability information.

    :param entity_id: The ID of the entity to update.
    :param asset: The asset containing the software and vulnerability information to update.
    """
    update_url = f"{ENTITY_UPDATE_URL}/{entity_id}/context"
    # Construct the payload with software and vulnerability details
    payload = {
        "context": {
            "os": asset["os"],
            "software": [s for s in asset["software"] if s else ""],
            "ips": [ips for ips in asset["addresses"] if ips else ""],
            "vulnerabilities": [{"name": v.get("name", ""), "cve": v.get("cve", ""), "severity": v.get("severity", "")} for v in asset.get("vulnerabilities", [])]
        }
    }
    
    # Make the API request to update the entity
    response = requests.post(update_url, headers=RF_HEADERS, json=payload)
    
    # Check the response status
    if response.status_code == 200:
        print(f"Entity {entity_id} updated successfully in Recorded Future.")
    else:
        print(f"Error updating entity: {response.text}")

# Function to create a new entity in Recorded Future
def create_entity_in_rf(asset):
    """
    Creates a new entity in Recorded Future based on the provided asset details.

    :param asset: The asset containing the details to create the entity with.
    """
    # Construct the entity to create
    formatted_entity = {
        "entity": {
            "id": f"uuid:{asset['id']}",
            "name": asset['names'][0],
            "type": "entity"
        },
        "context": {
            "os": asset['os'],
            "software": [s for s in asset['software'] if s else ""],
            "ips": [ips for ips in asset["addresses"] if ips else ""],
            "vulnerabilities": [{"name": v.get("name", ""), "cve": v.get("cve", ""), "severity": v.get("severity", "")} for v in asset.get("vulnerabilities", [])]
        }
    }
    
    # Make the API request to create the entity
    response = requests.post(LIST_API_URL, headers=RF_HEADERS, json={"entities": [formatted_entity]})
    
    # Check the response status
    if response.status_code == 200:
        print(f"Entity {asset['hostname'][0]} created successfully in Recorded Future.")
    else:
        print(f"Error creating entity: {response.text}")

# Main execution function
def main():
    """
    Main function to export data from runZero to Recorded Future.

    This function performs the following steps:
    1. Queries runZero for assets based on a specified search query.
    2. Enriches the retrieved assets with software and vulnerability information.
    3. Matches the enriched assets with Recorded Future entities.
    4. Updates existing entities or creates new ones in Recorded Future.

    :return: None
    """
    # Define the search query for assets
    search_query = "(type:=server OR type:laptop OR type:desktop) AND source:rapid7"
    
    # Query runZero for assets matching the search query
    assets = query_runzero_assets(search_query)

    # Check if any assets were found
    if not assets:
        print("No assets found.")
        return

    # Enrich assets with additional details
    enriched_assets = enrich_assets_with_details(assets)

    # Process each enriched asset
    for asset in enriched_assets:
        # Extract asset names and IPs
        asset_name = [name for name in asset['names'] if name] or [""]
        asset_ip = [ip for ip in asset['addresses'] if ip] or [""]

        # Match asset with Recorded Future entity
        rf_entity_id = match_entity_in_rf(asset_name, asset_ip)

        # Update existing entity or create a new one based on match results
        if rf_entity_id:
            print(f"Match found for {asset_name[0]}: {rf_entity_id}. Updating entity...")
            update_entity_in_rf(rf_entity_id, asset)
        else:
            print(f"No match found for {asset_name}, creating new entity...")
            create_entity_in_rf(asset)

if __name__ == "__main__":
    main()