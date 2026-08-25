# Custom Integration: BMC Helix CMDB Outbound

This outbound integration exports runZero assets and upserts CI records into
BMC Helix CMDB using the v2 `CONFIG` model.

## Requirements

- Superuser access to Custom Integrations in runZero.
- A runZero export token with access to the org asset export endpoint.
- Helix API credentials with permission to authenticate and create or update CI records.

## Parameters

- `runzero_export_token`: Bearer token used to export runZero assets.
- `helix_client_id`: Helix OAuth client ID.
- `helix_client_secret`: Helix OAuth client secret.
- `runzero_console_url`: runZero console base URL. Default: `https://console.runzero.com`.
- `runzero_search`: runZero export filter. Default: `alive:t`.
- `helix_api_base`: Helix API base URL.
- `helix_dataset_id`: Helix dataset ID. Default: `BMC.ASSET.SANDBOX`.
- `auth_login_path`, `cmdb_query_path`, `cmdb_create_path`, `cmdb_update_path`, `ast_attributes_path`: override API paths when needed. The default auth path is `/api/rx/authentication/oauth/token`.
- `post_ast_attributes`: optionally create `AST:Attributes` linkage records after upserts.
- `rz_http_*` / `rz_tls_*`: runZero HTTP and TLS options for export calls.
- `helix_http_*` / `helix_tls_*`: Helix HTTP and TLS options for destination API calls.

## Processing model

1. Export assets from runZero with the configured search filter.
2. Authenticate to Helix with a form-encoded OAuth `client_credentials` request.
3. Route each asset into the relevant Helix classes based on available fields.
4. Build class payloads from the embedded spreadsheet-derived mappings.
5. Upsert by hostname first, then serial number.

## Match behavior

- One Helix match: update the existing instance.
- Zero Helix matches: create a new instance.
- Multiple Helix matches: log a conflict and mark the record as failed.

## Mapping source

- `CLASS_FIELD_MAPPINGS` contains spreadsheet-derived field mappings.
- `LIFECYCLE_TO_BMC_STATUS` contains lifecycle-to-status translations.

## Notes

- This is an outbound integration; it performs remote writes and returns `None`.
- The script currently routes assets into the default five Helix classes embedded in the script.
- `/api/jwt/login` is a username/password JWT endpoint and is not compatible with the configured OAuth client ID and secret. Use the default OAuth path unless the Helix deployment provides a compatible client-credentials endpoint.

## References

- https://help.runzero.com/docs/custom-integration-scripts/
- https://help.runzero.com/docs/custom-integration-starlark-libraries/
