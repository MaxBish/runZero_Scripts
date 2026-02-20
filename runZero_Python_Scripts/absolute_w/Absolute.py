# --- Imports ---
import time
import json
import os
import requests
import re
from datetime import datetime, timedelta, timezone
from ipaddress import ip_address
from typing import List, Any, Dict

import runzero
from runzero.api import CustomAssets, Sites, CustomIntegrationsAdmin
from runzero.types import ImportAsset, NetworkInterface, ImportTask, IPv4Address, IPv6Address
from authlib.jose import JsonWebSignature

# --- Absolute Credentials ---
ABSOLUTE_TOKEN_ID = os.environ.get('ABSOLUTE_TOKEN_ID')
ABSOLUTE_TOKEN_SECRET = os.environ.get('ABSOLUTE_TOKEN_SECRET')
ABSOLUTE_BASE_URL = "https://api.us.absolute.com" # Example regional URL

# --- runZero Credentials ---
RUNZERO_ORG_ID = os.environ.get('RUNZERO_ORG_ID')
RUNZERO_SITE_NAME = 'Primary'
RUNZERO_CLIENT_ID = os.environ.get('RUNZERO_CLIENT_ID')
RUNZERO_CLIENT_SECRET = os.environ.get('RUNZERO_CLIENT_SECRET')

def flatten_json(d: Any, parent_key: str = '', sep: str = '_') -> Dict[str, str]:
    """
    Recursively flattens nested dictionaries and lists into a single level.
    This ensures that data like 'geoData.location.geoAddress.city' becomes 'location_city'.
    """
    items = []
    if isinstance(d, dict):
        for k, v in d.items():
            new_key = f"{parent_key}{sep}{k}" if parent_key else k
            if isinstance(v, (dict, list)):
                items.extend(flatten_json(v, new_key, sep=sep).items())
            else:
                # Only add if there is a value to avoid cluttering runZero with nulls
                if v is not None and v != "":
                    items.append((new_key, str(v)))
    elif isinstance(d, list):
        for i, v in enumerate(d):
            # Special handling for lists: append index to the key (e.g., disks_0_name)
            new_key = f"{parent_key}{sep}{i}"
            if isinstance(v, (dict, list)):
                items.extend(flatten_json(v, new_key, sep=sep).items())
            else:
                if v is not None and v != "":
                    items.append((new_key, str(v)))
    return dict(items)

def format_mac(mac: str) -> str:
    """Formats a raw string into a colon-delimited MAC address for runZero validation."""
    if not mac:
        return None
    clean_mac = re.sub(r'[^a-fA-F0-9]', '', mac)
    if len(clean_mac) == 12:
        return ":".join(clean_mac[i:i+2] for i in range(0, 12, 2))
    return None

def get_absolute_jws(method: str, uri: str, query_string: str, payload: Dict) -> str:
    """Constructs the JWS string required for Absolute API v3 authentication."""
    headers = {
        "alg": "HS256", 
        "kid": ABSOLUTE_TOKEN_ID,
        "method": method,
        "content-type": "application/json",
        "uri": uri,
        "query-string": query_string,
        "issuedAt": round(time.time() * 1000)
    }
    wrapped_payload = json.dumps({"data": payload}) if payload else json.dumps({})
    jws = JsonWebSignature()
    return jws.serialize_compact(headers, wrapped_payload, ABSOLUTE_TOKEN_SECRET)

def fetch_all_absolute_devices() -> List[Dict[str, Any]]:
    """Retrieves active devices seen within the last 3 days using comprehensive field selection."""
    all_devices = []
    next_page_token = None
    page_size = 500 
    uri = "/v3/reporting/devices"
    
    three_days_ago = (datetime.now(timezone.utc) - timedelta(days=60)).isoformat().replace('+00:00', 'Z')
    
    # Updated to request every relevant top-level object in the Absolute schema
    selected_fields = (
        "deviceUid,deviceName,platformOSType,systemManufacturer,systemModel,"
        "localIp,serialNumber,esn,agentStatus,username,isStolen,locale,"
        "operatingSystem,networkAdapters,espInfo,geoData,lastConnectedDateTimeUtc,"
        "battery,cpu,bios,memories,disks,displays,keyboards,printers,usbs,"
        "activeDirectoryData,customFields,rrCountSummary,sccmInfo,rsvpStatus,"
        "avpInfo,ctesVersion,agentVersion,pbVerErrorCodes, fullSystemName"
    )
    
    print(f"Beginning data retrieval from Absolute (Active since: {three_days_ago})...")
    while True:
        query_parts = [
            f"pageSize={page_size}", 
            "agentStatus=A",
            f"lastConnectedDateTimeUtcFromInclusive={three_days_ago}",
            f"select={selected_fields}"
        ]
        if next_page_token:
            query_parts.append(f"nextPage={next_page_token}")
        
        current_query_string = "&".join(query_parts)
        signed_jws = get_absolute_jws("GET", uri, current_query_string, {})
        
        url = f"{ABSOLUTE_BASE_URL}/jws/validate"
        
        response = requests.post(url, data=signed_jws, headers={"Content-Type": "text/plain"}, timeout=60)
        
        if response.status_code != 200:
            print(f"Error: {response.status_code} - {response.text}")
            break
            
        res_json = response.json()
        page_data = res_json.get("data", [])
        all_devices.extend(page_data)
        print(f"Downloaded {len(all_devices)} devices...")
        
        pagination = res_json.get("metadata", {}).get("pagination", {})
        next_page_token = pagination.get("nextPage")
        
        if not next_page_token:
            break 
            
    return all_devices

def build_network_interface(ips: List[str], mac: str = None) -> NetworkInterface:
    """Converts raw IP strings and formatted MAC into runZero NetworkInterface objects."""
    ip4s: List[IPv4Address] = []
    ip6s: List[IPv6Address] = []
    valid_mac = format_mac(mac)
    
    for ip in ips:
        if not ip: continue
        try:
            ip_obj = ip_address(ip)
            if ip_obj.version == 4: ip4s.append(IPv4Address(str(ip_obj)))
            elif ip_obj.version == 6: ip6s.append(IPv6Address(str(ip_obj)))
        except Exception: continue
            
    if valid_mac or ip4s or ip6s:
        return NetworkInterface(macAddress=valid_mac, ipv4Addresses=ip4s, ipv6Addresses=ip6s)
    return None

def build_runzero_assets(devices: List[Dict[str, Any]]) -> List[ImportAsset]:
    """Maps Absolute data to runZero assets with epoch timestamp conversion."""
    assets = []
    
    mapped_keys = {
        "deviceUid", "deviceName", "platformOSType", "systemManufacturer", 
        "systemModel", "networkAdapters", "localIp", "operatingSystem", "esn", "fullSystemName"
    }

    for d in devices:
        networks = []
        
        # 1. Map Network Interfaces
        adapters = d.get("networkAdapters", [])
        for adapter in adapters:
            ips = [ip for ip in [adapter.get("ipV4Address"), adapter.get("ipV6Address")] if ip]
            interface = build_network_interface(ips=ips, mac=adapter.get("macAddress"))
            if interface: networks.append(interface)
        
        if not networks and d.get("localIp"):
            interface = build_network_interface(ips=[str(d.get("localIp"))])
            if interface: networks.append(interface)

        # 2. Flatten and Filter Custom Attributes
        raw_flat = flatten_json(d)
        custom_attrs = {}
        
        # --- Convert lastConnectedDateTimeUtc to Epoch ---
        iso_time = d.get("lastConnectedDateTimeUtc")
        if iso_time:
            try:
                dt = datetime.fromisoformat(iso_time.replace('Z', '+00:00'))
                # Create epoch timestamp (seconds)
                custom_attrs["lastConnectedTS"] = str(int(dt.timestamp()))
            except Exception as e:
                print(f"Warning: Could not parse timestamp {iso_time}: {e}")
        # -------------------------------------------------------------

        for key, value in raw_flat.items():
            base_key = key.split('_')[0]
            if base_key not in mapped_keys:
                custom_attrs[key] = value

        # 3. Build ImportAsset
        assets.append(
            ImportAsset(
                id=d.get("deviceUid"), 
                hostname=str(d.get("fullSystemName") or ""),
                os=str(d.get("platformOSType") or ""),
                osVersion=str(d.get("operatingSystem", {}).get("version") or ""),
                manufacturer=str(d.get("systemManufacturer") or ""),
                model=str(d.get("systemModel") or ""),
                networkInterfaces=networks,
                customAttributes=custom_attrs
            )
        )
    return assets

# --- Main Execution ---

if __name__ == "__main__":
    raw_devices = fetch_all_absolute_devices()
    print(f"Final Count: {len(raw_devices)} devices retrieved.")

    if raw_devices:
        runzero_assets = build_runzero_assets(raw_devices)
        
        c = runzero.Client()
        c.oauth_login(RUNZERO_CLIENT_ID, RUNZERO_CLIENT_SECRET)
        
        custom_source_mgr = CustomIntegrationsAdmin(c)
        my_asset_source = custom_source_mgr.get(name="Absolute")
        if not my_asset_source:
            my_asset_source = custom_source_mgr.create(name="Absolute")
        
        site_mgr = Sites(c)
        site = site_mgr.get(RUNZERO_ORG_ID, RUNZERO_SITE_NAME)
        
        import_mgr = CustomAssets(c)
        import_mgr.upload_assets(
            org_id=RUNZERO_ORG_ID,
            site_id=site.id,
            custom_integration_id=my_asset_source.id, 
            assets=runzero_assets,
            task_info=ImportTask(name="Absolute Inventory Full Attribute Sync"),
        )
        print(f"Successfully submitted {len(runzero_assets)} assets with full attributes to runZero.")