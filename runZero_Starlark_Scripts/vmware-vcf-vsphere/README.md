# VMware VCF and vSphere

Inbound runZero Starlark integration targeting VCF 5.2.4 SDDC Manager and
vSphere 8.0.3 vCenter REST APIs. Requires runZero `5.1.260818.0` or later.

## Setup

Create a custom integration using `vmware-vcf-vsphere.star`, then create its
credential and schedule a task on an Explorer that can reach the management API.
Use separate credentials/tasks for SDDC Manager and each vCenter. This script
does not discover vCenters and automatically send credentials to them.

| Parameter | Value |
| --- | --- |
| `mode` | `vcf` for SDDC Manager, or `vsphere` for vCenter |
| `url` | HTTPS base URL, such as `https://sddc.example.com` or `https://vcenter.example.com`; no API path |
| `source_scope` | Unique, stable installation label, such as `production-vcenter-01`; keep it unchanged between runs |
| `username` | SSO/AD username accepted by the selected endpoint |
| `password` | Password; stored as a secret |
| `guest_details` | Read VMware Tools guest hostname, OS, and IP data; default `true`, vSphere only |
| `vapi_metadata` | Read registered vAPI component/package names; default `true`, vSphere only |
| `cluster_ids` | Optional comma-separated vSphere cluster IDs to restrict hosts and VMs |
| `tls_*`, `http_*` | Standard runZero TLS and HTTP options |

Use a trusted CA with `tls_ca_cert` for private certificates. TLS validation is
enabled by default. Username and password are both secret fields and are never
included in imported attributes or script messages.

VCF authentication uses `POST /v1/tokens`, then Bearer authentication. The VCF
account must have a role allowing inventory reads; the token documentation lists
VIEWER, OPERATOR, and ADMIN. Start with the least privileged permitted role.
vSphere authentication uses Basic authentication for `POST /api/session`, then
the `vmware-api-session-id` header. Grant inventory read access, including
`System.Read` on VMs. Appliance/version and metadata reads may need additional
permissions in the customer deployment.

## Imported Data

VCF mode imports:

- ESXi hosts: FQDN, IP addresses, physical NIC MACs, ESXi version, hardware
  vendor/model, serial number attribute, domain/cluster IDs and names, status.
- vCenter appliances listed in workload domains, SDDC Manager appliances, and
  individual NSX Manager nodes. NSX VIPs are not emitted as separate appliances.
- ESXi software versions and source-reported components/add-ons when the host
  response includes `softwareInfo`. Missing fields are left empty.

vSphere mode imports:

- ESXi host summaries: hostname, connection state, power state, and resource ID.
- VMs: instance/BIOS UUIDs, administrative display name as an attribute, power
  state, CPU/memory, virtual hardware version, and virtual NIC MACs.
- Guest hostname, OS name, and IP addresses when VMware Tools data is available.
  VM display names are not treated as DNS hostnames.
- The configured vCenter appliance with version/build and registered vAPI
  component/package names as attributes.

vAPI metamodel packages describe API namespaces, not installed RPMs, VIBs, or
guest application inventory. They are deliberately not reported as software.
Starlark cannot load an external VMware SDK package; this script calls the
documented REST APIs directly. VCF software components reflect the source's
reported image information, not an independent scan of installed packages.

## Asset Identity

### Virtual Machines

- Target entity: one VM instance managed by one vCenter.
- Source field: VM detail `identity.instance_uuid`, not the BIOS UUID or `vm-*`
  resource reference.
- Evidence: Broadcom defines this as the VirtualCenter-specific UUID that
  uniquely identifies VM instances, including VMs sharing an SMBIOS UUID.
- Scope/cardinality: one VM per instance UUID within a vCenter installation.
- Stability: ordinary polls retain the ID while that instance UUID is unchanged.
  Clone, restore, re-registration, and cross-vCenter migration behavior must be
  checked in the customer environment; continuity across those events is not
  promised. The reference does not specify deleted UUID recycling.
- Presence: the identity block is optional; missing instance UUIDs are skipped.
- Final ID: `vmware:vsphere:<source_scope>:vm:<instance_uuid>`.
- Match behavior: `no-ip-break no-name-break`; MAC disagreement remains a guard.
- Verdict: scoped authoritative for the vCenter-managed VM instance, not a
  lifetime-global identity of the guest installation.

### Hosts and Management Appliances

- Target entity: one host or appliance, not its cluster, domain, NIC, or VIP.
- Source fields: FQDN/host name plus the operator's stable source namespace.
- Evidence: inventory contracts identify these objects and their FQDNs, but do
  not establish lifecycle-stable foreign IDs or ID reuse guarantees.
- Scope/cardinality: one emitted record per hostname in the selected source;
  duplicate records are skipped. Different namespaces produce different IDs.
- Stability: IDs are deterministic while hostname and namespace remain unchanged.
  Renaming/recommissioning may change them; source IDs are attributes only.
- Final ID: `vmware:<source_scope>:<asset_type>:<hostname>`.
- Missing identity: skip records without a usable hostname; no random fallback.
- Match behavior: `no-id-match no-id-break` per asset type, layered on the
  integration's `no-ip-break no-name-break`. Network identifiers drive matching.
- Verdict: derived/non-authoritative. Hostname reuse and shared IPs remain
  correlation risks; check merge results during customer validation.

## Limits and Customer Validation

No live customer validation has been performed. Validate and run the script in
the intended customer environment with credentials entered directly in runZero.
Confirm inventory counts, permissions, asset merges, and stable IDs across two
polls before scheduling production imports.

vSphere 8.0.3 list APIs have no cursor: at most 2,500 hosts and 4,000 VMs may match
one request. Use `cluster_ids` and separate tasks for larger environments. The
script fails on API errors rather than silently truncating results.

The cited VCF inventory endpoints return `elements` and may include
`pageMetadata`, but document no paging request parameters. Collections indicating
multiple pages or more total elements than returned cause an explicit failure.
If encountered, obtain the customer's endpoint paging contract before enabling
paging; this script does not guess parameter names.

GET requests retry transient failures twice using runZero's bounded backoff.
Authentication is not retried. Optional enrichment returning 403, 404, or 503 is
skipped. Other failures terminate the task; assets already streamed may have
been reported. Sessions/refresh tokens are closed after successful collection;
an aborted run leaves them to expire. VCF access tokens expire after one hour;
this script does not refresh tokens mid-run.

Catalog regeneration is not applicable: this integration lives in the scripts
workspace, outside the generated `runzero-custom-integrations` catalog.

## References

- https://help.runzero.com/docs/custom-integration-scripts/
- https://help.runzero.com/docs/custom-integration-starlark-libraries/
- https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/tokens/
- https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/v1/hosts/get/
- https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/domains/
- https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/v1/clusters/get/
- https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/v1/sddc-managers/get/
- https://developer.broadcom.com/xapis/vmware-cloud-foundation-api/latest/v1/nsxt-clusters/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/cis/api/session/post/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vcenter/api/vcenter/host/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vcenter/api/vcenter/vm/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vcenter/api/vcenter/vm/vm/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vcenter/data-structures/Vm_Identity_Info/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vcenter/api/vcenter/vm/vm/guest/identity/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vcenter/api/vcenter/vm/vm/guest/networking/interfaces/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/appliance/api/appliance/system/version/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vapi/api/vapi/metadata/metamodel/component/get/
- https://developer.broadcom.com/xapis/vsphere-automation-api/8.0.3/vapi/api/vapi/metadata/metamodel/package/get/