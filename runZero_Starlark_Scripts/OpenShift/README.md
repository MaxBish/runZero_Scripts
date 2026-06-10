## OpenShift Custom Integration for runZero

This custom integration queries the OpenShift/Kubernetes API and imports cluster nodes into runZero as assets—complete with hostnames, internal and external IPs, OS information, kernel versions, architecture, topology labels, and hardware correlation identifiers. A global `DEBUG` flag controls verbose logging.

---

## Features

* **Node Discovery**

  * Fetches all cluster nodes via `/api/v1/nodes`
  * Automatically paginates large clusters using the Kubernetes `continue` token

* **Network Interfaces**

  * Extracts `InternalIP` and `ExternalIP` from `status.addresses`
  * Filters out loopback (`127.*`, `::1`) and link-local (`169.254.*`, `fe80:`) addresses

* **OS & Runtime Information**

  * Captures OS image (e.g. `Red Hat Enterprise Linux CoreOS 4.14.12`), kernel version, container runtime, kubelet version

* **Node Role Detection**

  * Derives `master` / `worker` role from `node-role.kubernetes.io/*` labels

* **Hardware Correlation**

  * Captures `systemUUID` (SMBIOS UUID) and `machineID` to help runZero correlate nodes with scan-discovered assets

* **Topology Awareness**

  * Reads `topology.kubernetes.io/region` and `topology.kubernetes.io/zone` labels (falls back to legacy `failure-domain.beta.kubernetes.io/*` keys)

* **Insecure TLS**

  * Global `INSECURE_ALLOWED = True|False` for clusters with self-signed certificates (common in on-prem OpenShift deployments)

* **Debug Logging**

  * Global `DEBUG = True|False` toggles verbose per-node print output

---

## Prerequisites

### 1. OpenShift Service Account Token

Create a service account with read-only access to nodes and generate a bearer token.

```bash
# Create a service account in a dedicated namespace
oc create serviceaccount runzero-integration -n default

# Bind the built-in cluster-reader role (read-only, cluster-wide)
oc create clusterrolebinding runzero-integration \
  --clusterrole=cluster-reader \
  --serviceaccount=default:runzero-integration

# Get the bearer token (OpenShift 4.11+)
oc create token runzero-integration -n default --duration=8760h
```

> **Minimum required permissions:** `get` and `list` on `nodes` at the cluster scope. The built-in `cluster-reader` role satisfies this and nothing more is needed for node-only sync.

### 2. OpenShift API URL

Find your cluster's API URL:

```bash
oc whoami --show-server
# Example output: https://api.cluster.example.com:6443
```

### 3. runZero Console

1. **Credentials** → **Add Credential** → **Custom Script Secret**

   * **Access Key**: any placeholder (e.g. `openshift`)
   * **Access Secret**: your JSON config blob (see below)

2. **Integrations** → **Custom Integrations** → **Add Script**

   * Paste the contents of `openshift.star`
   * Save and attach the credential

---

## Configuration

Set **Access Secret** to the following JSON (as a single-line string):

```json
{"base_url":"https://api.cluster.example.com:6443","access_secret":"<service-account-bearer-token>"}
```

| Field           | Description                                                           |
| --------------- | --------------------------------------------------------------------- |
| `base_url`      | OpenShift API URL including port, e.g. `https://api.cluster.com:6443` |
| `access_secret` | Bearer token from the service account                                 |

---

## Script Entry Point

```python
# Toggle debug prints on or off
DEBUG = True

def main(*args, **kwargs):
    """
    OpenShift custom integration: syncs cluster nodes into runZero.

    Credentials — set access_secret to a JSON blob:
      {
        "base_url":      "https://api.cluster.example.com:6443",
        "access_secret": "<service-account-bearer-token>"
      }
    """
```

---

## Testing with the runZero CLI

```bash
runzero script --filename openshift.star \
  --kwargs access_secret='{"base_url":"https://api.cluster.example.com:6443","access_secret":"<token>"}'
```

Enable debug output by setting `DEBUG = True` at the top of the file before running.

Use the REPL for interactive testing:

```bash
runzero script repl --filename openshift.star
```

---

## Asset Data Mapped to runZero

| runZero Field        | OpenShift Source                          |
| -------------------- | ----------------------------------------- |
| `id`                 | `metadata.uid`                            |
| `hostnames`          | `metadata.name`                           |
| `networkInterfaces`  | `status.addresses` (InternalIP, ExternalIP) |
| `os`                 | `status.nodeInfo.operatingSystem`         |
| `osVersion`          | `status.nodeInfo.osImage`                 |
| `manufacturer`       | `Red Hat` (static)                        |
| `model`              | `OpenShift Node` (static)                 |
| `deviceType`         | `Server` (static)                         |
| `tags`               | `openshift`, `node`, `master`/`worker`    |

### Custom Attributes

| Attribute                        | Source                                      |
| -------------------------------- | ------------------------------------------- |
| `openshift_node_name`            | `metadata.name`                             |
| `openshift_role`                 | `node-role.kubernetes.io/*` labels          |
| `openshift_ready_status`         | `status.conditions[type=Ready].status`      |
| `openshift_kernel_version`       | `status.nodeInfo.kernelVersion`             |
| `openshift_os_image`             | `status.nodeInfo.osImage`                   |
| `openshift_container_runtime`    | `status.nodeInfo.containerRuntimeVersion`   |
| `openshift_kubelet_version`      | `status.nodeInfo.kubeletVersion`            |
| `openshift_kube_proxy_version`   | `status.nodeInfo.kubeProxyVersion`          |
| `openshift_architecture`         | `status.nodeInfo.architecture`              |
| `openshift_region`               | `topology.kubernetes.io/region` label       |
| `openshift_zone`                 | `topology.kubernetes.io/zone` label         |
| `openshift_system_uuid`          | `status.nodeInfo.systemUUID` (SMBIOS UUID)  |
| `openshift_machine_id`           | `status.nodeInfo.machineID`                 |

> **Note:** Physical hardware details (CPU model, RAM, serial number) are not exposed by the OpenShift/Kubernetes API. `openshift_system_uuid` (SMBIOS UUID) is the closest hardware fingerprint available and can help runZero correlate API-imported nodes with assets discovered via network scanning.

---

## Extending the Integration

* **Pod Discovery**: Query `/api/v1/pods` to import running workloads as additional assets
* **Namespace Filtering**: Add a `?fieldSelector=metadata.namespace=<ns>` param to `fetch_nodes` to scope to specific projects
* **Additional Labels**: Surface any custom OpenShift labels as `customAttributes` by iterating `metadata.labels`

---

## Support

For help, contact your runZero administrator or see the [runZero Custom Integration docs](https://help.runzero.com/docs/custom-integration-scripts/).
