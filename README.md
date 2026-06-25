# cp4ba-opensearch-dashboard

Utilities for IBM Cloud Pak® for Business Automation

<i>Last update: 2026-06-25</i> (see changelog.md for details)



The contents must be understood as examples of training on the topic of CP4BA IT Operations. 

Obviously it is without any kind of support. Use them freely, modify them where necessary according to your needs.

This repository can be useful for professionals who create disposable environments dedicated to demonstrations/tests of the CP4BA product (IBMers, IBM Partners and Customers with active license to access to IBM Container Registry).

Please read the DISCLAIMER section carefully.

This repository was created to simplify my IBM CP4BA study and PoX activities.

Even if the installations as per the IBM user manual are relatively simple, they must always be contextualized in the various deployment combinations.


## Table of Contents

1. [Introduction and Scope](#1-introduction-and-scope)
2. [Repository Structure](#2-repository-structure)
3. [Script Reference](#3-script-reference)
   - [3.1 cp4ba-os-install-dashboard.sh](#31-cp4ba-os-install-dashboardsh)
   - [3.2 cp4ba-os-dashboard-infos.sh](#32-cp4ba-os-dashboard-infossh)
   - [3.3 cp4ba-os-remove-dashboard.sh](#33-cp4ba-os-remove-dashboardsh)
4. [Prerequisites and Dependencies](#4-prerequisites-and-dependencies)
5. [Kubernetes / OpenShift Objects Managed](#5-kubernetes--openshift-objects-managed)
6. [Architecture Overview](#6-architecture-overview)
7. [Typical Workflow](#7-typical-workflow)

---

## 1. Introduction and Scope

### What is this repository?

`cp4ba-opensearch-dashboard` is a **companion toolset** for IBM Cloud Pak for Business Automation (CP4BA). It provides a set of Bash scripts that deploy, configure, and manage an **OpenSearch Dashboards** instance on top of an existing OpenSearch cluster that is already provisioned and managed by CP4BA.

### Problem it solves

IBM CP4BA ships with an embedded OpenSearch cluster (managed through the `opensearch-operator`) for storing and querying operational data such as business event logs, audit trails, and BAI (Business Automation Insights) indices. However, CP4BA does **not** ship with a pre-deployed OpenSearch Dashboards UI. This tool fills that gap by:

- Auto-discovering the credentials and TLS certificates from the existing CP4BA OpenSearch cluster.
- Deploying a fully configured, TLS-secured OpenSearch Dashboards pod inside the **same OpenShift namespace** as CP4BA.
- Exposing the dashboard via an OpenShift `Route` with TLS passthrough.
- Providing a simple one-command teardown to clean up all created resources.

### Supported platform

| Component | Version / Notes |
|---|---|
| Platform | OpenShift Container Platform (OCP) |
| CLI tool | `oc` (OpenShift CLI) |
| OpenSearch Dashboards image | `opensearchproject/opensearch-dashboards:2.19.0` |
| CP4BA OpenSearch operator | Resources assumed present: `cluster/opensearch`, `opensearch-tls-secret-route` |
| Supporting tools | `jq`, `base64` |

> **Note:** Although the scripts use the `oc` CLI, the objects created are standard Kubernetes resources (Deployment, Service, ConfigMap, Secret, ServiceAccount) and the patterns are directly applicable to any Kubernetes cluster that uses `kubectl` with minor adaptations.

---

## 2. Repository Structure

```
cp4ba-opensearch-dashboard/
├── README.md                              
└── scripts/
    ├── cp4ba-os-install-dashboard.sh      # Installs the OpenSearch Dashboards instance
    ├── cp4ba-os-dashboard-infos.sh        # Prints connection URL and credentials
    └── cp4ba-os-remove-dashboard.sh       # Removes all installed resources
```

---

## 3. Script Reference

---

### 3.1 `cp4ba-os-install-dashboard.sh`

**Location:** `scripts/cp4ba-os-install-dashboard.sh`

#### Purpose

This is the **main installation script**. It automates the full lifecycle required to stand up a working OpenSearch Dashboards instance connected to the existing CP4BA-managed OpenSearch cluster. It handles credential discovery, certificate extraction, Kubernetes object creation, and route exposure — all in a single execution.

#### What it does — step by step

| Step | Action | Details |
|------|--------|---------|
| 1 | **Discover credentials** | Reads the `opensearch` custom resource (CR) in the target namespace to find the name of the internal user secret, then extracts the username (first key in the secret's `.data` map) and decodes the base64-encoded password. |
| 2 | **Compute service hostname** | Builds the in-cluster DNS name for the OpenSearch service: `opensearch.<namespace>.svc.cluster.local`. |
| 3 | **Create ServiceAccount** | Creates `opensearch-dashboards` ServiceAccount in the target namespace. |
| 4 | **Grant `anyuid` SCC** | Runs `oc adm policy add-scc-to-user anyuid` on the new ServiceAccount so that the container can run as the UID expected by the upstream OpenSearch Dashboards image. This is required in OpenShift's restricted-by-default security model. |
| 5 | **Create credentials Secret** | Creates `opensearch-dashboards-credentials` generic Secret with the discovered `username` and `password` literals. |
| 6 | **Extract TLS certificates** | Reads `ca.crt`, `tls.crt`, and `tls.key` from the existing `opensearch-tls-secret-route` Secret, decodes them, writes them to `/tmp`, and then creates the `opensearch-dashboards-certs` Secret. |
| 7 | **Create ConfigMap** | Applies `opensearch-dashboards-config` ConfigMap containing `opensearch_dashboards.yml`. Key settings: server listens on `0.0.0.0:5601` with TLS enabled, connects to OpenSearch via HTTPS with `certificate` SSL verification mode, injects the discovered username/password, and sets logging level to `warn`. |
| 8 | **Create Deployment** | Applies the `opensearch-dashboards` Deployment (1 replica, image `opensearchproject/opensearch-dashboards:2.19.0`). The pod: mounts the ConfigMap as `opensearch_dashboards.yml` and the certs Secret as a directory, injects credentials as environment variables (`OPENSEARCH_USERNAME`, `OPENSEARCH_PASSWORD`), disables the built-in Security Dashboards plugin (`DISABLE_SECURITY_DASHBOARDS_PLUGIN=true`), and runs as non-root with resource limits (CPU: 200m–1000m, Memory: 512Mi–1Gi). |
| 9 | **Create Service** | Applies a `ClusterIP` Service `opensearch-dashboards` on port 5601, selecting pods labelled `app: opensearch-dashboards`. |
| 10 | **Create Route** | Applies an OpenShift `Route` `opensearch-dashboard` with TLS **passthrough** termination (the TLS session is not terminated at the router; it goes directly to the pod) and `insecureEdgeTerminationPolicy: Redirect`. |

#### Key configuration values (embedded in the ConfigMap)

```yaml
server.name: opensearch-dashboards
server.host: "0.0.0.0"
server.port: 5601
server.ssl.enabled: true
server.ssl.certificate: /usr/share/opensearch-dashboards/config/certs/cert.crt
server.ssl.key: /usr/share/opensearch-dashboards/config/certs/key.crt

opensearch.hosts: ["https://opensearch.<namespace>.svc.cluster.local:9200"]
opensearch.ssl.verificationMode: certificate
opensearch.ssl.certificate: /usr/share/opensearch-dashboards/config/certs/cert.crt
opensearch.ssl.key: /usr/share/opensearch-dashboards/config/certs/key.crt
opensearch.ssl.certificateAuthorities: ["/usr/share/opensearch-dashboards/config/certs/ca.crt"]
opensearch.username: "<auto-discovered>"
opensearch.password: "<auto-discovered>"
logging.root.level: warn
```

> **Note:** The configuration contains a commented-out alternative `opensearch.ssl.verificationMode: none`. This can be useful for debugging in development environments where certificate validation is not required.

#### Usage

```bash
./scripts/cp4ba-os-install-dashboard.sh <NAMESPACE>
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<NAMESPACE>` | Yes | The OpenShift project/namespace where CP4BA and the OpenSearch cluster are deployed. |

**Example:**

```bash
# Install the OpenSearch Dashboards in the 'cp4ba-prod' namespace
./scripts/cp4ba-os-install-dashboard.sh cp4ba-prod
```

**Expected output:**

```
Install Opensearch dashboard
Done
```

> All `oc` commands redirect stdout and stderr to `/dev/null`, so individual step errors are silent. Verify success with `oc get pods -n <namespace> | grep opensearch-dashboards`.

**Verify installation:**

```bash
# Check pod is running
oc get pods -n cp4ba-prod -l app=opensearch-dashboards

# Check the route was created
oc get route opensearch-dashboard -n cp4ba-prod

# Get the full URL
oc get route opensearch-dashboard -n cp4ba-prod -o jsonpath='{.spec.host}'
```

---

### 3.2 `cp4ba-os-dashboard-infos.sh`

**Location:** `scripts/cp4ba-os-dashboard-infos.sh`

#### Purpose

A **diagnostic / information script** that prints the external access URL and the login credentials for the deployed OpenSearch Dashboards instance. It reads the same sources used during installation (the OpenSearch CR and its referenced secret) so credentials are always up-to-date.

#### What it does — step by step

| Step | Action | Details |
|------|--------|---------|
| 1 | **Discover credentials** | Same logic as the install script: reads the `opensearch` CR → finds the internal user Secret name → extracts username (first key) → base64-decodes the password. |
| 2 | **Resolve Dashboard URL** | Reads the `spec.host` of the `opensearch-dashboard` OpenShift Route and prefixes it with `https://`. |
| 3 | **Print information** | Outputs the Dashboard URL and the `username / password` pair to stdout. |

#### Usage

```bash
./scripts/cp4ba-os-dashboard-infos.sh <NAMESPACE>
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<NAMESPACE>` | Yes | The OpenShift project/namespace where CP4BA and the OpenSearch Dashboards are deployed. |

**Example:**

```bash
./scripts/cp4ba-os-dashboard-infos.sh cp4ba-prod
```

**Expected output:**

```
Opensearch dashboard infos
Dashboard https://opensearch-dashboard-cp4ba-prod.apps.cluster.example.com
Credentials admin / s3cr3tP@ssw0rd
Done
```

**Typical use cases:**
- Quickly retrieve the URL after installation to open in a browser.
- Retrieve credentials to share with an operator or for scripted login.
- Validate that the Route and Secret are accessible after a cluster restart.

---

### 3.3 `cp4ba-os-remove-dashboard.sh`

**Location:** `scripts/cp4ba-os-remove-dashboard.sh`

#### Purpose

A **teardown script** that cleanly removes **all** Kubernetes/OpenShift resources that were created by `cp4ba-os-install-dashboard.sh`. All deletions are idempotent: the script suppresses "not found" errors so it is safe to run even if some resources have already been deleted.

#### What it does — step by step

The script calls `oc delete` for each resource in sequence:

| Order | Resource Kind | Name | Description |
|-------|--------------|------|-------------|
| 1 | `ServiceAccount` | `opensearch-dashboards` | Removes the dedicated service account (the `anyuid` SCC binding is also removed automatically by OpenShift when the SA is deleted). |
| 2 | `ConfigMap` | `opensearch-dashboards-config` | Removes the `opensearch_dashboards.yml` configuration. |
| 3 | `Secret` | `opensearch-dashboards-credentials` | Removes the username/password secret. |
| 4 | `Secret` | `opensearch-dashboards-certs` | Removes the TLS certificate secret. |
| 5 | `Deployment` | `opensearch-dashboards` | Terminates and removes the dashboard pod(s). |
| 6 | `Service` | `opensearch-dashboards` | Removes the ClusterIP service. |
| 7 | `Route` | `opensearch-dashboard` | Removes the external HTTPS route. |

> **Note:** The script does **not** remove the `anyuid` SCC policy explicitly via `oc adm policy remove-scc-from-user`. In practice, OpenShift automatically cleans this up when the ServiceAccount is deleted.

#### Usage

```bash
./scripts/cp4ba-os-remove-dashboard.sh <NAMESPACE>
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<NAMESPACE>` | Yes | The OpenShift project/namespace from which to remove the OpenSearch Dashboards resources. |

**Example:**

```bash
./scripts/cp4ba-os-remove-dashboard.sh cp4ba-prod
```

**Expected output:**

```
Remove Opensearch dashboard
Done
```

**Verify removal:**

```bash
oc get all -n cp4ba-prod -l app=opensearch-dashboards
# Should return: No resources found
```

---

## 4. Prerequisites and Dependencies

Before running any script, ensure the following are in place:

### CLI tools

| Tool | Purpose | Install reference |
|------|---------|-------------------|
| `oc` | OpenShift CLI — all resource operations | [OpenShift CLI docs](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |
| `jq` | JSON query — used to extract the username key from the secret | [jq download](https://stedolan.github.io/jq/) |
| `base64` | Decode base64-encoded certificate and password data | Standard on Linux/macOS |

### OpenShift / CP4BA prerequisites

| Prerequisite | Details |
|---|---|
| Logged-in `oc` session | `oc login` with sufficient permissions (project admin or cluster admin for SCC operations). |
| CP4BA installed namespace | The target namespace must already have the CP4BA OpenSearch cluster deployed. |
| `cluster/opensearch` CR | Must exist in the target namespace with `spec.plugins.security.internalUserSecret` populated. |
| `opensearch-tls-secret-route` Secret | Must exist in the target namespace with `ca.crt`, `tls.crt`, and `tls.key` entries. |
| `anyuid` SCC permission | The executing user must have `cluster-admin` or sufficient rights to run `oc adm policy add-scc-to-user`. |
| Internet / registry access | The OpenShift cluster must be able to pull `opensearchproject/opensearch-dashboards:2.19.0` from Docker Hub (or a configured mirror). |

---

## 5. Kubernetes / OpenShift Objects Managed

The following table summarises all objects touched by the toolset:

| Object Kind | Name | Created by | Deleted by |
|---|---|---|---|
| `ServiceAccount` | `opensearch-dashboards` | install | remove |
| `ClusterRole binding` (SCC) | `anyuid` on SA | install (via `oc adm policy`) | remove (implicit on SA delete) |
| `Secret` (generic) | `opensearch-dashboards-credentials` | install | remove |
| `Secret` (generic) | `opensearch-dashboards-certs` | install | remove |
| `ConfigMap` | `opensearch-dashboards-config` | install | remove |
| `Deployment` | `opensearch-dashboards` | install | remove |
| `Service` (ClusterIP) | `opensearch-dashboards` | install | remove |
| `Route` (passthrough) | `opensearch-dashboard` | install | remove |

---

## 6. Architecture Overview

```
 OpenShift Cluster
 ┌────────────────────────────────────────────────────────────┐
 │  Namespace: cp4ba-prod                                     │
 │                                                            │
 │  ┌──────────────────────┐   HTTPS:9200   ┌─────────────┐   │
 │  │ OpenSearch Dashboards│ ─────────────► │  OpenSearch │   │
 │  │ Pod (port 5601)      │  (mTLS via     │  Cluster    │   │
 │  │ image: 2.19.0        │   certs secret)│  (CP4BA)    │   │
 │  └──────────┬───────────┘                └─────────────┘   │
 │             │ ClusterIP Service :5601                      │
 │             ▼                                              │
 │  ┌──────────────────────┐                                  │
 │  │ Service              │                                  │
 │  │ opensearch-dashboards│                                  │
 │  └──────────┬───────────┘                                  │
 │             │ TLS Passthrough Route                        │
 │             ▼                                              │
 │  ┌──────────────────────┐                                  │
 │  │ Route                │                                  │
 │  │ opensearch-dashboard │                                  │
 └──┼──────────────────────┼──────────────────────────────────┘
    │  HTTPS (passthrough) │
    ▼                      
  External Browser / Client
```

**TLS flow:**  
The OpenShift Router forwards raw TLS traffic to the pod without decrypting it (passthrough mode). The pod itself terminates TLS using the certificates stored in `opensearch-dashboards-certs`. The same certificates are also used by the pod when connecting to the OpenSearch backend, enabling mutual TLS verification.

---

## 7. Typical Workflow

```bash
# 1. Log in to your OpenShift cluster
oc login https://api.my-cluster.example.com:6443 -u kubeadmin

# 2. Set the target namespace (CP4BA project)
export NS=cp4ba-prod

# 3. Install the OpenSearch Dashboards
./scripts/cp4ba-os-install-dashboard.sh $NS

# 4. Wait for the pod to become Ready
oc rollout status deployment/opensearch-dashboards -n $NS

# 5. Retrieve the access URL and credentials
./scripts/cp4ba-os-dashboard-infos.sh $NS

# 6. Open the URL in a browser and log in with the displayed credentials

# --- Later, when no longer needed ---

# 7. Remove all resources
./scripts/cp4ba-os-remove-dashboard.sh $NS
```

---
**DISCLAIMER**


<u>The entire contents of this repository are not intended for production environments.</u>

The main purpose is self-education and for test or demo environments.
No form of support or warranty is applicable.

Only the <b>.sh</b> scripts and <b>.properties</b> configuration files are released in open source mode according to https://opensource.org/license/mit/

<i>Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge , publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.</i>

The configurations for CR .yaml deployment 

    apiVersion: icp4a.ibm.com/v1

    kind: ICP4ACluster

are property of IBM as per the official wording:

Licensed Materials - Property of IBM

(C) Copyright IBM Corp. 2022, 2023. All Rights Reserved.

US Government Users Restricted Rights - Use, duplication or
disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

---
