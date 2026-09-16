# Custom Integration: BMC Helix CMDB Outbound

This outbound integration exports runZero assets and upserts CI records into
BMC Helix CMDB using the v2 `CONFIG` model.

## Requirements

- Superuser access to Custom Integrations in runZero.
- A runZero export token with access to the org asset export endpoint.
- Helix API credentials with permission to authenticate and create or update CI records.

## Parameters

- `runzero_export_token`: Bearer token used to export runZero assets.
- `helix_client_id`: Helix RSSO OAuth client ID.
- `helix_client_secret`: Helix RSSO OAuth client secret (used for HTTP Basic auth on the token request).
- `helix_jwt_private_key`: unencrypted PEM private key used to sign the JWT assertion. This is the private key behind the runZero console's own TLS certificate — its matching public key/certificate is what was already extracted and given to the BMC RSSO team for PREAUTH validation, so no separate key pair needs to be generated. This Starlark JWT module cannot decrypt a passphrase-protected PEM, so the key must be stored here unencrypted; runZero encrypts secret params at rest. Treat this value as highly sensitive: it is the console's TLS private key, not a purpose-built signing key, so scope access to this integration's config tightly and rotate it if the console's certificate is ever rotated or the key is suspected of exposure.
- `helix_jwt_algorithm`: JWT signing algorithm. Default: `RS256`.
- `helix_jwt_subject`: RSSO login ID sent as the JWT `sub` claim. Default: `runzero-apiaccess`.
- `helix_token_audience`: the RSSO realm's Application Domain, sent as the `audience` form parameter on the token request. Confirm the exact value with Helix Ops.
- `runzero_console_url`: runZero console base URL. Default: `https://console.runzero.com`.
- `runzero_search`: runZero export filter. Default: `alive:t`.
- `helix_api_base`: Helix REST API base URL, for example `https://servicedeskonline-dev-restapi.onbmc.com`.
- `helix_auth_base`: Helix SSO base URL, for example `https://au-rsso1-dev.onbmc.com/rsso`.
- `helix_dataset_id`: Helix dataset ID. Default: `BMC.ASSET.SANDBOX`.
- `auth_login_path`, `cmdb_query_path`, `cmdb_create_path`, `cmdb_update_path`, `ast_attributes_path`: override API paths when needed. The default token path is `/oauth2/v1.1/token` and the default CMDB paths use `/api/cmdb/v1.0/instance`.
- `post_ast_attributes`: optionally create `AST:Attributes` linkage records after upserts.
- `rz_http_*` / `rz_tls_*`: runZero HTTP and TLS options for export calls.
- `helix_http_*` / `helix_tls_*`: Helix HTTP and TLS options for destination API calls.

## Processing model

1. Export assets from runZero with the configured search filter.
2. Build a signed JWT assertion (`sub`/`aud`/`iss`/`iat`/`exp`/`jti`, `aud` = the token endpoint URL) and exchange it at the Helix RSSO token endpoint using the `urn:ietf:params:oauth:grant-type:jwt-bearer` grant, with the client ID/secret sent as HTTP Basic auth and the Application Domain sent as the `audience` form parameter.
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
- Authentication uses BMC's RSSO PREAUTH OAuth JWT Assertion (JWT bearer) grant, not a browser-based Authorization Code flow, so no interactive login or callback is required. The JWT is signed with the runZero console's existing TLS private key; BMC has already been given the matching public key/certificate pulled from that TLS certificate and has enabled PREAUTH for the target realm.
- Because this reuses the console's TLS private key for JWT signing (rather than a key generated solely for this integration), rotating the console's TLS certificate requires updating both `helix_jwt_private_key` here and the public certificate on file with BMC RSSO.

## References

- https://help.runzero.com/docs/custom-integration-scripts/
- https://help.runzero.com/docs/custom-integration-starlark-libraries/
- https://community.bmc.com/s/article/Authenticate-to-OAuth2-0-for-usage-in-Helix-ITSM-REST-API
