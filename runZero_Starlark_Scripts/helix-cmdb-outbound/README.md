# runZero to BMC Helix CMDB (Starter)

This is a starter outbound custom integration script that exports assets from runZero and upserts CIs into BMC Helix CMDB.

Current matching and write behavior:
- Primary match: hostname/FQDN
- Secondary fallback match: serial number
- If exactly one match is found: update existing CI
- If no match is found: create net-new CI
- If multiple matches are found: mark as failed and log conflict

Current class routing behavior:
- `helix_class_routing=true` (default) routes each asset to one or more Helix classes based on available runZero data:
  - `BMC_ComputerSystem` (always)
  - `BMC_OperatingSystem` (when OS fields exist)
  - `BMC_IPEndpoint` (when IPs exist)
  - `BMC_LANEndpoint` (when MACs exist)
  - `BMC_HardwareSystemComponent` (when serial/manufacturer/model exists)
- `helix_class_name` can force a single class; when routing is enabled, that class still requires matching data shape.
- `helix_class_routing=false` enforces single-class mode.

## Important notes

- This starter uses placeholder Helix endpoint paths and field mappings.
- Update endpoint templates, class/dataset values, and mapping table before production use.
- Keep dry-run enabled until your Helix sandbox confirms update and create paths.

## runZero requirements

- Superuser access to Custom Integrations in runZero
- Hosted explorer to execute the task
- Export token (ET) or equivalent token with access to export endpoint

## Credential and kwargs layout

Use a Custom Script Secret credential and pass values via kwargs.

Required for runZero export:
- runzero_export_token (or fallback access_secret)
- runzero_console_url (optional, defaults to https://console.runzero.com)
- runzero_search (optional runZero search query)

Required for Helix live mode:
- helix_api_base
- helix_client_id
- helix_client_secret
- helix_class_name
- helix_dataset_id

Optional endpoint overrides:
- helix_oauth_token_path (default /api/oauth2/token)
- helix_cmdb_query_path (default /api/cmdb/v1/instance/{className})
- helix_cmdb_create_path (default /api/cmdb/v1/instance/{className})
- helix_cmdb_update_path (default /api/cmdb/v1/instance/{className}/{instanceId})

Optional runtime toggle:
- dry_run=true|false (default true)
- helix_class_routing=true|false (default true)

Optional defaults for mapped values:
- helix_company
- helix_supported_default (default Yes)
- helix_primary_capability (default Server)
- helix_ip_category (default Network)
- helix_os_category (default Software)
- helix_lan_category (default Network)

## Mapping table

The script now includes extracted sheet-based mappings and lifecycle translation from runzero_helix_mapping.xlsx:
- class maps in `CLASS_FIELD_MAPPINGS`
- lifecycle map in `LIFECYCLE_TO_BMC_STATUS`

Edit `GLOBAL_MAPPING_FIELDS` and `CLASS_FIELD_MAPPINGS` in custom-integration-helix-cmdb-outbound.star to align with your final workbook decisions.

Example format:
- 'runzero_field_name': 'HelixAttributeName'

Recommended first fields:
- hostname/FQDN equivalents
- serial number
- manufacturer/model
- OS and OS version
- any reconciliation or source tracking attributes required by your Helix class

Lifecycle translation currently implemented:
- Planned for introduction -> Reserved
- Implemented -> Being Assembled
- Live in production -> Deployed
- Planned to remove -> Down
- Decommissioned -> End of Life

## How to run locally with runZero CLI

Dry-run example:

runzero script --filename custom-integration-helix-cmdb-outbound.star \
  --kwargs runzero_export_token=<RUNZERO_EXPORT_TOKEN> \
  --kwargs runzero_console_url=https://console.runzero.com \
  --kwargs runzero_search='alive:t' \
  --kwargs helix_api_base=https://<HELIX_HOST> \
  --kwargs helix_client_id=<CLIENT_ID> \
  --kwargs helix_client_secret=<CLIENT_SECRET> \
  --kwargs helix_class_name=<CLASS_NAME> \
  --kwargs helix_dataset_id=<DATASET_ID> \
  --kwargs dry_run=true

Live-mode example:

runzero script --filename custom-integration-helix-cmdb-outbound.star \
  --kwargs runzero_export_token=<RUNZERO_EXPORT_TOKEN> \
  --kwargs runzero_console_url=https://console.runzero.com \
  --kwargs runzero_search='alive:t' \
  --kwargs helix_api_base=https://<HELIX_HOST> \
  --kwargs helix_client_id=<CLIENT_ID> \
  --kwargs helix_client_secret=<CLIENT_SECRET> \
  --kwargs helix_class_name=<CLASS_NAME> \
  --kwargs helix_dataset_id=<DATASET_ID> \
  --kwargs dry_run=false

## Next hardening items

- Replace placeholder endpoint templates with your tenant-confirmed Helix API paths.
- Confirm query parameter names for hostname and serial filters in your Helix API.
- Add retry/backoff for transient failures and rate limits.
- Add batch controls for very large exports.
- Add dead-letter output for conflict/failed writes.
