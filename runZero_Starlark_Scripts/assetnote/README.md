# AssetNote

This inbound custom integration imports AssetNote IP, subdomain, and cloud assets
into runZero from the AssetNote GraphQL API.

## Setup

Generate an API key manually in the AssetNote console. Configure the integration
with the instance name (the subdomain in
`https://<instance>.assetnotecloud.com`) and the API key. The script sends
`X-ASSETNOTE-API-KEY` to
`https://<instance>.assetnotecloud.com/api/v2/graphql`. The Explorer must be
able to reach this endpoint.

Parameters:

- `instance`: required AssetNote instance DNS label; also namespaces imported IDs.
- `api_key`: required secret API key.
- `url`: optional full GraphQL endpoint override, including `/api/v2/graphql`;
  useful for controlled test endpoints. It does not change the identity namespace.
- `page_size`: assets per page, 1-25; defaults to 25.
- `http_*` and `tls_*`: shared runZero HTTP and TLS options.

## Imported data

Each GraphQL `assets.edges[].node` becomes at most one runZero asset. The script
maps the AssetNote ID, IP address on IP assets, `host` or `subdomain` as a
hostname when valid, source asset type, creation and last-updated timestamps,
and selected custom attributes: human name, asset type, asset group ID and
name, exposure rating, online and monitoring flags, verification, and
importance. Missing IDs are skipped. It does not import services, technologies,
findings, certificates, or nested integration account data. In particular,
third-party tokens and secrets in those account objects are never requested or
copied into custom attributes or logs.

The import reads all assets, including unverified assets, on every run. It
sorts by ID and requests one-based pages until `pageInfo.hasNextPage` is false;
`pager()` guards the walk with a 100,000-page limit. Results are streamed to
runZero as they arrive. A `created`-based checkpoint would miss changes to
existing assets, so this script deliberately has no checkpoint or persistent
state. Read-only GraphQL requests use the HTTP helper's bounded transient
retries.

## Asset identity

- Target entity: one AssetNote inventory asset per `assets.edges[].node`.
- Source ID: `node.id`, requested on `BaseAsset`.
- Evidence: the provided GraphQL query lists assets ordered by `id`, and the
  supplied asset example includes an `id`. The integration owner confirmed
  that IDs are stable and unique within an instance across asset types and
  repeated polls.
- Uniqueness scope: one AssetNote instance.
- Cardinality: one GraphQL node per AssetNote asset. Nested records are not
  emitted as separate assets.
- Stability: confirmed across ordinary repeated polls and renames by the
  integration owner; vendor guarantees on deletion, reassignment, and reuse
  have not been provided.
- Presence: expected for an asset; rows without an ID are skipped.
- Final runZero ID: `assetnote:<instance>:<node.id>` (no fallback).
- Match behavior: `no-mac-break no-ip-break no-name-break`; the source ID
  remains the authoritative key while names and addresses may change.
- Verdict: instance-scoped authoritative ID on the stated owner confirmation,
  subject to the unverified vendor lifecycle caveat above.

## Validation

On a runZero CLI with the 5.1 custom integration features:

```sh
runzero script --filename assetnote/assetnote.star --validate
```

The generic HTTP validator checks CONFIG and HTTP option wiring, not the
AssetNote schema. Also check with a controlled GraphQL fixture or a test
instance: multiple pages, stable IDs across runs, a malformed row, GraphQL and
HTTP errors, and absence of integration-account secrets in emitted assets.
The CLI installed in this workspace does not currently support `--validate`.

## References

- The AssetNote asset example, tested GraphQL query, and API-key authentication
  supplied with this integration request. No public vendor API contract was
  supplied; confirm schema and ID lifecycle behavior against your instance.
- [runZero custom integration scripts](https://help.runzero.com/docs/custom-integration-scripts/)
- [runZero Starlark libraries](https://help.runzero.com/docs/custom-integration-starlark-libraries/)