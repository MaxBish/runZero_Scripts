import requests
import csv
import os
from datetime import datetime, timezone

# --- Configuration ---
EMPTY = " "
API_KEY = os.getenv('RUNZERO_API_KEY')
API_BASE_URL = 'https://console.runzero.com/api/v1.0/org/assets'
CSV_FILENAME = 'Asset_data.csv'
SAVE_LOCATION = 'downloads'
REQUEST_TIMEOUT_SECONDS = 60
FIELDS = 'names,foreign_attributes'
SEARCH = '(type:laptop or type:desktop or type:workstation or type:"thin client") and not (source_count:=1 and custom_integration:Netskope)'

COLUMN_NAMES = [
    'hostname', 'intune_username', 'intune_userPrincipalName',
    'intune_serial_number', 'intune_id', 'intune_first_seen_timestamp', 'intune_last_seen_timestamp',
    'crowdstrike_lastInteractiveUser', 'crowdstrike_serial_number', 'crowdstrike_id', 'crowdstrike_lastSeen', 'crowdstrike_firstSeen', 'crowdstrike_agentVersion',
    'absolute_username', 'absolute_serial_number', 'absolute_id', 'absolute_lastConnectedDateTimeUtc', 'absolute_agent_version',
    'absolute_encryption_product', 'absolute_encryption_status', 'absolute_encryption_status_description',
    'azure_ad_id', 'azure_ad_first_observed_timestamp', 'azure_ad_last_observed_timestamp',
    'rapid7_id', 'rapid7_first_seen_timestamp', 'rapid7_last_seen_timestamp', 'netskope_id', 'netskope_last_seenTS', 'netskope_serial_number'
]

if SAVE_LOCATION == 'downloads':
    OUTPUT_FILENAME = os.path.expanduser(f'~/Downloads/{CSV_FILENAME}')
else:
    OUTPUT_FILENAME = os.path.expanduser(f'~/Desktop/{CSV_FILENAME}')

HEADERS = {
    'Authorization': f'Bearer {API_KEY}',
    'Accept': 'application/json',
}


def first_integration_record(foreign_attributes, integration_key):
    """Return the first integration record for a foreign attribute key, or {}."""
    records = foreign_attributes.get(integration_key, [])
    return records[0] if records else {}


def to_text(value):
    """Normalize None/empty values to the CSV placeholder value."""
    if value is None or value == "":
        return EMPTY
    return value


def safe_date(ts_value):
    """Safely convert epoch timestamps to UTC ISO strings."""
    try:
        if ts_value:
            return datetime.fromtimestamp(int(ts_value), tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    except (ValueError, TypeError):
        pass
    return EMPTY


def build_asset_row(asset):
    """Build one CSV row from a runZero asset object."""
    foreign_attributes = asset.get('foreign_attributes', {})
    names = asset.get('names', [])
    hostname = names[0] if names else EMPTY

    intune = first_integration_record(foreign_attributes, '@intune.dev')
    crowdstrike = first_integration_record(foreign_attributes, '@crowdstrike.dev')
    absolute = first_integration_record(foreign_attributes, '@absolute.custom')
    azure = first_integration_record(foreign_attributes, '@azuread.dev')
    rapid7 = first_integration_record(foreign_attributes, '@rapid7.dev')
    netskope = first_integration_record(foreign_attributes, '@netskope.custom')

    return [
        hostname,
        to_text(intune.get('userDisplayName')),
        to_text(intune.get('userPrincipalName')),
        to_text(intune.get('serialNumber')),
        to_text(intune.get('id')),
        safe_date(intune.get('enrolledDateTimeTS')),
        safe_date(intune.get('lastSyncDateTimeTS')),
        to_text(crowdstrike.get('lastInteractiveUser')),
        to_text(crowdstrike.get('serialNumber')),
        to_text(crowdstrike.get('id')),
        to_text(crowdstrike.get('lastSeen')),
        to_text(crowdstrike.get('firstSeen')),
        to_text(crowdstrike.get('agentVersion')),
        to_text(absolute.get('username')),
        to_text(absolute.get('serialNumber')),
        to_text(absolute.get('id')),
        to_text(absolute.get('lastConnectedDateTimeUtc')),
        to_text(absolute.get('agentVersion')),
        to_text(absolute.get('espInfoEncryptionProductName')),
        to_text(absolute.get('espInfoEncryptionStatus')),
        to_text(absolute.get('espInfoEncryptionStatusDescription')),
        to_text(azure.get('id')),
        safe_date(azure.get('registrationDateTimeTS')),
        safe_date(azure.get('approximateLastSignInDateTimeTS')),
        to_text(rapid7.get('id')),
        safe_date(rapid7.get('report.startTimeTS')),
        safe_date(rapid7.get('report.endTimeTS')),
        to_text(netskope.get('id')),
        to_text(netskope.get('netskopeTS')),
        to_text(netskope.get('serialNumber')),
    ]

def main():
    if not API_KEY:
        print('Missing RUNZERO_API_KEY environment variable.')
        return

    response = requests.get(
        API_BASE_URL,
        headers=HEADERS,
        params={'search': SEARCH, 'fields': FIELDS},
        timeout=REQUEST_TIMEOUT_SECONDS,
    )

    if response.status_code != 200:
        print(f"Failed to fetch data: {response.status_code} - {response.text}")
        return

    data = response.json()
    rows = [build_asset_row(asset) for asset in data]

    with open(OUTPUT_FILENAME, 'w', newline='', encoding='utf-8') as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(COLUMN_NAMES)
        writer.writerows(rows)

    print(f"Successfully exported {len(rows)} assets to {OUTPUT_FILENAME}")

if __name__ == "__main__":
    main()