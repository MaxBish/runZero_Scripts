import requests
import csv
import json
import os
from datetime import datetime, timezone

# --- CONFIGURATION ---
API_KEY = os.getenv('RUNZERO_API_KEY') 
API_BASE_URL = f'https://console.runzero.com/api/v1.0/org/assets'
CSV_FILENAME = 'Asset_data.csv'
SAVE_LOCATION = 'downloads' 

if SAVE_LOCATION == 'downloads':
    OUTPUT_FILENAME = os.path.expanduser(f'~/Downloads/{CSV_FILENAME}')
else:
    OUTPUT_FILENAME = os.path.expanduser(f'~/Desktop/{CSV_FILENAME}')

headers = {
    'Authorization': f'Bearer {API_KEY}',
    'Accept': 'application/json'
}

search = 'type:desktop or type:laptop or type:workstation or type:"thin client"'

def safe_date(ts_value):
    """Helper to safely convert timestamps to ISO strings."""
    try:
        if ts_value:
            return datetime.fromtimestamp(int(ts_value), tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    except (ValueError, TypeError):
        pass
    return " "

def main():
    response = requests.get(API_BASE_URL, headers=headers, params={'search': search, 'fields': 'names,foreign_attributes'})

    if response.status_code == 200:
        data = response.json()
        
        column_names = [
            'hostname', 'intune_username', 'intune_userPrincipalName', 
            'intune_serial_number', 'intune_id', 'intune_first_seen_timestamp', 'intune_last_seen_timestamp',
            'crowdstrike_lastInteractiveUser', 'crowdstrike_serial_number', 'crowdstrike_id', 'crowdstrike_lastSeen', 'crowdstrike_firstSeen', 'crowdstrike_agentVersion',
            'absolute_username', 'absolute_serial_number', 'absolute_id', 'absolute_lastConnectedDateTimeUtc', 'absolute_agent_version',
            'azure_ad_id', 'azure_ad_first_observed_timestamp', 'azure_ad_last_observed_timestamp',
            'rapid7_id', 'rapid7_first_seen_timestamp', 'rapid7_last_seen_timestamp'
        ]
        
        rows = []

        for asset in data[:25]:
            # Safely get foreign_attributes dict
            fa = asset.get('foreign_attributes', {})
            
            # --- General Info ---
            names = asset.get('names', [])
            hostname = names[0] if names else " "

            # --- Intune Logic ---
            intune_list = fa.get('@intune.dev', [])
            if intune_list:
                i = intune_list[0]
                intune_username = i.get('userDisplayName', " ")
                intune_userPrincipalName = i.get('userPrincipalName', " ")
                intune_serial_number = i.get('serialNumber', " ")
                intune_id = i.get('id', " ")
                intune_first_seen_timestamp = safe_date(i.get('enrolledDateTimeTS'))
                intune_last_seen_timestamp = safe_date(i.get('lastSyncDateTimeTS'))
            else:
                intune_username = intune_userPrincipalName = intune_serial_number = intune_id = " "
                intune_first_seen_timestamp = intune_last_seen_timestamp = " "

            # --- CrowdStrike Logic ---
            cs_list = fa.get('@crowdstrike.dev', [])
            if cs_list:
                c = cs_list[0]
                crowdstrike_lastInteractiveUser = c.get('lastInteractiveUser', " ")
                crowdstrike_serial_number = c.get('serialNumber', " ")
                crowdstrike_id = c.get('id', " ")
                crowdstrike_lastSeen = c.get('lastSeen', " ")
                crowdstrike_firstSeen = c.get('firstSeen', " ")
                crowdstrike_agentVersion = c.get('agentVersion', " ")
            else:
                crowdstrike_lastInteractiveUser = crowdstrike_serial_number = crowdstrike_id = " "
                crowdstrike_lastSeen = crowdstrike_firstSeen = crowdstrike_agentVersion = " "

            # --- Absolute Logic ---
            abs_list = fa.get('@absolute.custom', [])
            if abs_list:
                a = abs_list[0]
                absolute_username = a.get('username', " ")
                absolute_serial_number = a.get('serialNumber', " ")
                absolute_id = a.get('id', " ")
                absolute_lastConnectedDateTimeUtc = a.get('lastConnectedDateTimeUtc', " ")
                absolute_agent_version = a.get('agentVersion', " ")
            else:
                absolute_username = absolute_serial_number = absolute_id = " "
                absolute_lastConnectedDateTimeUtc = absolute_agent_version = " "

            # --- Azure AD Logic ---
            azure_list = fa.get('@azuread.dev', [])
            if azure_list:
                z = azure_list[0]
                azure_ad_id = z.get('id', " ")
                azure_ad_first_observed_timestamp = safe_date(z.get('registrationDateTimeTS'))
                azure_ad_last_observed_timestamp = safe_date(z.get('approximateLastSignInDateTimeTS'))
            else:
                azure_ad_id = " "
                azure_ad_first_observed_timestamp = azure_ad_last_observed_timestamp = " "

            # --- Rapid7 Logic ---
            r7_list = fa.get('@rapid7.dev', [])
            if r7_list:
                r = r7_list[0]
                rapid7_id = r.get('id', " ")
                rapid7_first_seen_timestamp = safe_date(r.get('report.startTimeTS'))
                rapid7_last_seen_timestamp = safe_date(r.get('report.endTimeTS'))
            else:
                rapid7_id = " "
                rapid7_first_seen_timestamp = rapid7_last_seen_timestamp = " "

            # Assemble row
            row = [
                hostname, intune_username, intune_userPrincipalName, 
                intune_serial_number, intune_id, intune_first_seen_timestamp, intune_last_seen_timestamp,
                crowdstrike_lastInteractiveUser, crowdstrike_serial_number, crowdstrike_id, crowdstrike_lastSeen, crowdstrike_firstSeen, crowdstrike_agentVersion,
                absolute_username, absolute_serial_number, absolute_id, absolute_lastConnectedDateTimeUtc, absolute_agent_version,
                azure_ad_id, azure_ad_first_observed_timestamp, azure_ad_last_observed_timestamp,
                rapid7_id, rapid7_first_seen_timestamp, rapid7_last_seen_timestamp
            ]
            rows.append(row)

        # Write CSV
        with open(OUTPUT_FILENAME, 'w', newline='', encoding='utf-8') as csv_file:
            writer = csv.writer(csv_file)
            writer.writerow(column_names)
            writer.writerows(rows)
        print(f"Successfully exported {len(rows)} assets to {OUTPUT_FILENAME}")
    else:
        print(f"Failed to fetch data: {response.status_code} - {response.text}")

if __name__ == "__main__":
    main()