# runZero Console Asset Sync

This custom integration exports all assets from a source runZero console and returns them as `ImportAsset` objects for ingestion into the destination console.

## runZero requirements

- Superuser access to [Custom Integrations](https://console.runzero.com/custom-integrations)
- A hosted explorer for the task

## Source console requirements

- An export token for the source organization
- The source console URL, for example `https://console.runzero.com`

## Credential layout

Create a Custom Script Secret credential with:

- `access_key`: source console URL
- `access_secret`: source export token

If `access_key` is empty, the script defaults to `https://console.runzero.com`.

## What the script preserves

- Source asset ID as the stable `ImportAsset.id`
- Hostnames
- IP addresses and MAC addresses via `NetworkInterface`
- OS and OS version
- Device type, manufacturer, and model when present
- Tags
- First seen timestamp when the source value can be parsed by runZero
- Source last seen and other source-only fields as custom attributes

## Out of scope for this version

- Service information
- Software inventory
- Vulnerabilities

Those fields can be revisited later if the source export and destination import model support them cleanly.

## Steps

1. Create the credential.
2. Create a new custom integration in [Custom Integrations](https://console.runzero.com/custom-integrations/new).
3. Enable the custom integration script and paste the `.star` file contents.
4. Create a task under [Custom integrations ingest](https://console.runzero.com/ingest/custom/).
5. Select the credential, pick a hosted explorer, and schedule the task.

## Notes

- The script currently pulls the full `/api/v1.0/export/org/assets.json` export.
- Asset identity is based on the source asset ID, so recurring runs should update the same imported asset rather than inventing a new one.
- `last_seen` is retained as a custom attribute because the importer is not relying on a dedicated last-seen field.
