# Custom Integration: Trellix Asset Importer

This integration script connects to the FireEye Helix/HX API to retrieve host asset information and import it into runZero as assets.

## runZero requirements

* Superuser access to the [Custom Integrations configuration](https://console.runzero.com/custom-integrations) in runZero.
* An Explorer available to run the scheduled task.

---

## Trellix / FireEye HX requirements

* **FireEye API Credentials:** A username and password with permissions to access the host/asset inventory API endpoint (`/hx/api/v3/hosts`).
* **FireEye Base URL:** The base URL for your FireEye instance (e.g., `https://fireeye-hx.example.com`). This must be configured directly within the script's `FIREEYE_BASE_URL` constant.

---

## Steps

### Trellix / FireEye HX Configuration

1.  **Identify API Credentials:** Ensure you have a valid **username and password** with read access to the Host API endpoint.
2.  **Configure the Script URL:** Open the script and replace the placeholder `XXXXXXXXXXXXXXX` in the `FIREEYE_BASE_URL` constant with your actual FireEye instance URL.

    > **Example (Must be updated in the script):**
    > ```python
    > # Constants for the FireEye API
    > FIREEYE_BASE_URL = "[https://your-fireeye-instance.com](https://your-fireeye-instance.com)" 
    > HOSTS_ENDPOINT "{}/hx/api/v3/hosts".format(FIREEYE_BASE_URL)
    > ```

### runZero Configuration

1.  **Create a Credential for the Custom Integration**:
    * Go to [runZero Credentials](https://console.runzero.com/credentials).
    * Select `Custom Integration Script Secrets`.
    * Enter your FireEye API credentials as the `access_secret` in the format: `username:password` (e.g., `apiuser:P@ssw0rd123`).
    * Use a placeholder value like `foo` for `access_key` (unused in this integration).
2.  **Create the Custom Integration**:
    * Go to [runZero Custom Integrations](https://console.runzero.com/custom-integrations/new).
    * Add a **Name and Icon** for the integration (e.g., "Trellix").
    * Toggle `Enable custom integration script` and input the finalized script code.
    * Click `Validate` and then `Save`.
3.  **Schedule the Integration Task**:
    * Go to [runZero Ingest](https://console.runzero.com/ingest/custom/).
    * Select the **Credential and Custom Integration** created earlier.
    * Set a schedule for recurring updates (e.g., daily).
    * Select the **Explorer** where the script will run.
    * Click **Save** to start the task.

---

### What's next?

* The task will appear and kick off on the [tasks](https://console.runzero.com/tasks) page.
* Assets in runZero will be created or updated based on **Trellix host inventory**.
* The script captures details like **hostname, OS, primary IP, and MAC address**.
* Search for these assets in runZero using `custom_integration:fireeye hx`.

---

### Notes on Data Handling

* The script uses **Basic Authentication** (encoded `username:password`) for API access.
* The integration handles **pagination** automatically, iterating through all available pages of hosts from the `/hx/api/v3/hosts` endpoint.
* All fields from the Trellix / FireEye host record that are not explicitly mapped (like `_id`, `hostname`, `os`, `ip`, `mac`) are saved into runZero's **Custom Attributes**.
