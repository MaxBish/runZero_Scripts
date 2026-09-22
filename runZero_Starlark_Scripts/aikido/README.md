# Aikido Security

This inbound custom integration imports Aikido cloud assets, virtual machines,
and endpoint-protection devices as separate runZero asset types.

## Requirements

- Create REST API client credentials in Aikido.
- Grant `clouds:read`, `virtual_machines:read`, and
	`endpoint_protection:read` scopes.
- Allow the selected Explorer to reach the Aikido OAuth and regional API hosts.

## Parameters

- `url`: regional public API base URL. The default is the Europe API.
- `token_url`: OAuth client-credentials endpoint.
- `client_id` and `client_secret`: Aikido REST API client credentials.
- `page_size`: cloud assets per request, from 10 through 100.

## Imported objects

- `/clouds/assets`: cloud inventory records, provider, region, source ID, and
	optional metadata.
- `/virtual-machines`: virtual machines, OS, OS version, cloud, region,
	environment, purpose, and issue counts.
- `/endpoint-protection/devices`: endpoint devices, OS, serial number, user,
	agent version, group, heartbeat, and status.

Cloud assets use the documented `hasMore` and zero-based `page` parameters.
The virtual-machine and endpoint-device endpoints are imported as documented
list responses.

## Asset identity

- Target entities: cloud resources, virtual machines, and endpoint devices.
- Source ID fields: `clouds/assets[].id`, `virtual-machines[].id`, and
	`endpoint-protection/devices[].id`.
- Documentation evidence: [Aikido cloud assets](https://apidocs.aikido.dev/reference/getcloudassets),
	[Aikido virtual machines](https://apidocs.aikido.dev/reference/listvirtualmachines),
	and [Aikido endpoint devices](https://apidocs.aikido.dev/reference/listendpointprotectiondevices)
	describe each field as the Aikido object/device ID.
- Uniqueness scope: Aikido workspace; asset population is included in the ID
	namespace so IDs from different populations cannot collide.
- Cardinality: one documented inventory object per emitted asset. Findings and
	cloud metadata remain enrichment data rather than separate assets.
- Stability: the API documentation establishes object identity but does not
	document behavior across rename, reprovision, deletion, reconnect, or ID
	reuse. Confirm these lifecycle semantics with Aikido before treating the
	source IDs as permanently authoritative.
- Presence: each endpoint schema documents `id` as required; records without an
	ID are skipped.
- Final runZero IDs: `aikido:cloud:<id>`,
	`aikido:virtual-machine:<id>`, and `aikido:endpoint-device:<id>`.
- Missing-ID behavior: skip the record; no random fallback is used.
- Match behavior: `no-mac-break no-ip-break no-name-break`, because names and
	network identifiers are enrichment fields that can change independently.
- Verdict: provisional authoritative, pending confirmation of Aikido ID
	lifecycle and reuse behavior.

## Validation

```bash
runzero script --filename aikido/aikido.star --validate
```

The local workspace CLI currently lacks `--validate` and the v2 `pager`
builtin, so live validation must use a newer Explorer/CLI build. Editor
diagnostics are clean.

## Documentation

- [Aikido authorization](https://apidocs.aikido.dev/reference/authorization)
- [Get access token](https://apidocs.aikido.dev/reference/getaccesstoken)
- [Aikido API documentation](https://apidocs.aikido.dev/)