# OpenStack Nova Asset Importer (runZero Custom Integration)

This script is a runZero custom integration designed to fetch virtual machine (VM) data from an **OpenStack Compute (Nova) API** endpoint and import them as assets into your runZero inventory.

It authenticates using the **OpenStack Identity (Keystone)** API, retrieves server details, and maps key information like IP addresses, MAC addresses, hostnames, OS details, and custom OpenStack attributes to runZero asset fields.

---

## Prerequisites

To use this script, you'll need:

1.  An **OpenStack** environment.
2.  A user account with permissions to access the **Identity (Keystone)** and **Compute (Nova)** APIs.
3.  A **runZero Explorer** with **Custom Integration** support.

---

## Setup Instructions

Follow these steps to configure and run the integration.

### 1. Configure OpenStack API Endpoints in the Script

You must update the base URLs in the script to match your OpenStack environment before deploying it.

Locate the following lines near the top of the script and replace `<your-openstack-host>` with the actual hostname or IP address of your OpenStack endpoint.

# You must update these base URLs to match your OpenStack environment.
# Identity (keystone): 5000, Compute (nova): 8774
IDENTITY_API_BASE_URL = "https://<your-openstack-host>:5000"
COMPUTE_API_BASE_URL = "https://<your-openstack-host>:8774"

### 2. Create the Custom Integration in runZero

1.  Log into your **runZero Console**.
2.  Navigate to **Account**, then **Custom Integrations**.
3.  Click **New Integration**.
4.  Give your integration a descriptive **Name** (e.g., "OpenStack").
6.  Paste the entire contents of your OpenStack script into the **script** window.
7.  Click **Save**.

### 3. Set Up the Integration Task

1.  Go back to the **Tasks** page
2.  Click **New Integration** and select **Custom Script**.
3.  Select the **Explorer** you want to use to run the integration, and define the **Credential** and **Integration Script** you want to use.
4.  Click **Save & Run** to execute the integration.