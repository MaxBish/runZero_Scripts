# Zscaler Analytics Inbound PoC for runZero

This is a private proof-of-concept inbound custom integration that imports asset-like records from Zscaler Analytics GraphQL responses into runZero.

## Scope

- Inbound only
- Assets only (hostname, IP, MAC, OS)
- No software or vulnerability import in this phase

## Files

- config.json
- custom-integration-zscaler.star

## What to update before running

Edit the constants at the top of custom-integration-zscaler.star:

- ZSCALER_TOKEN_URL
- ZSCALER_GRAPHQL_URL
- ZSCALER_AUDIENCE
- ZSCALER_GRAPHQL_QUERY

The script supports either:

1. OAuth client credentials using access_key and access_secret
2. Direct bearer token in access_secret (leave access_key empty)

For OAuth mode, the token request sends the required audience parameter for Zscaler OneAPI.

## Credential mapping in runZero

Use Custom Script Secret credentials:

- access_key: client id (or blank when using direct bearer token)
- access_secret: client secret or bearer token

## Runtime behavior

- Sends GraphQL requests to the Analytics endpoint
- Recursively extracts candidate records from GraphQL data payloads
- Normalizes fields from flexible response shapes:
  - IDs: id, deviceId, endpointId, assetId, machineId
  - Hostname: hostname, hostName, name, deviceName, fqdn
  - IPs: ip, ipAddress, ipv4, ipv6, addresses
  - MAC: macAddress, mac, mac_address, primaryMac, macAddresses
- Builds deterministic fallback IDs from hostname/IP when provider ID is missing

## Validation checklist

1. Run with a small API scope first and confirm task success.
2. Confirm imported assets include stable IDs and expected hostnames/IPs.
3. Rerun and confirm duplicates are not created.
4. Adjust the GraphQL query and field mapping constants for your chosen Zscaler Analytics domain.

## Notes

- This is a PoC starter and assumes your selected GraphQL query returns endpoint-level identities.
- If your chosen Analytics domain only returns aggregates, update the query to return per-record fields before ingestion.
