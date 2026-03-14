# Hyperledger Fabric on OpenShift — CertChain Demo

> A multi-org blockchain demo running **Hyperledger Fabric 3.1** with BFT consensus,
> per-org Keycloak identity, and GitOps deployment on **Red Hat OpenShift**.

This project demonstrates how to deploy and operate a [Hyperledger Fabric](https://www.hyperledger.org/projects/fabric) permissioned blockchain network on OpenShift. It covers multi-organization governance with BFT consensus, per-org identity isolation via Keycloak, GitOps-driven deployment with ArgoCD, and a full observability stack. **CertChain** — a certificate credentialing system — is the sample use case that ties it all together.

---

## What Does This Demo Show?

- **Hyperledger Fabric 3.1** multi-org network with 4 BFT orderers, 3 peers, and CouchDB state databases
- **Per-org namespace isolation** — each organization gets its own Keycloak, APIs, UI, and blockchain peer
- **Identity brokering** — students log in once and are auto-routed to their institute's identity provider
- **Certificate ownership privacy** — grade and degree visible only to the certificate owner; public verification shows status and basic info only
- **Role-based access control** — admin dashboards enforce `org-admin` role; students see "Access Denied"
- **GitOps deployment** — Helm App-of-Apps pattern deployed via ArgoCD (RHDP-ready)
- **Observability** — Prometheus metrics from Fabric and Quarkus, Grafana dashboards
- **Resilience** — pod self-healing, multi-org isolation, blockchain decentralization

### The Sample Scenario

Three fictional training institutes issue tamper-proof course certificates on a shared blockchain ledger:

| Institute | Focus | Sample Courses |
|---|---|---|
| **TechPulse Academy** | Software development | Full-Stack Web Dev, Cloud-Native Microservices, DevSecOps |
| **DataForge Institute** | Data & databases | PostgreSQL Admin, Data Pipeline Engineering, Graph DBs |
| **NeuralPath Labs** | AI / ML | Applied ML, LLM Fine-Tuning, Computer Vision |

Three types of users interact with the system:

| Who | What they do | Login required? |
|---|---|---|
| **Registrar** (org staff) | Issues and revokes certificates via a branded dashboard (requires `org-admin` role) | Yes — org-specific login |
| **Employer** | Verifies a certificate by entering its ID or scanning a QR code (sees public info only — no grade/degree) | No — fully anonymous |
| **Student** | Views their full transcript across all institutes (sees grade/degree only on their own certificates) | Yes — auto-routed to their institute's login |

### The Flow

```
 Registrar                    Blockchain                 Employer / Student
 ─────────                    ──────────                 ──────────────────
     │                             │                            │
     │  Issue certificate          │                            │
     │────────────────────────────►│                            │
     │                             │  Recorded on ledger        │
     │                             │                            │
     │                             │       Verify by cert ID    │
     │                             │◄───────────────────────────│
     │                             │       ✓ VALID / ✗ REVOKED  │
     │                             │───────────────────────────►│
     │                             │                            │
     │  Revoke certificate         │                            │
     │────────────────────────────►│                            │
     │                             │  Status updated on ledger  │
     │                             │                            │
     │                             │       Re-verify            │
     │                             │◄───────────────────────────│
     │                             │       ✗ REVOKED            │
     │                             │───────────────────────────►│
```

---

## Architecture

Each institute gets its own isolated namespace with its own identity provider, dashboard, and blockchain peer. Central services handle cross-org verification and student identity brokering.

```
                          ┌─────────────────────────────────────────────┐
                          │            certchain  (central)             │
                          │                                             │
                          │  ┌─────────────┐    ┌──────────────────┐   │
                          │  │  Keycloak    │    │   cert-portal    │   │
                          │  │  (central)   │    │   (React PWA)    │   │
                          │  │  • ID broker │    │   • Verify certs │   │
                          │  │  • Org route │    │   • QR scanner   │   │
                          │  └──────┬───┬──┘    │   • Transcripts  │   │
                          │         │   │       └────────┬─────────┘   │
                          │         │   │                │              │
                          │  ┌──────┴───┴──┐    ┌───────┴──────────┐   │
                          │  │  orderer0   │    │   verify-api     │   │
                          │  │  (BFT)      │    │   (Quarkus)      │   │
                          │  └─────────────┘    └──────────────────┘   │
                          │  ┌─────────────┐    ┌──────────────────┐   │
                          │  │  fabric-ca  │    │  certcontract    │   │
                          │  │  (PKI)      │    │  (Go chaincode)  │   │
                          │  └─────────────┘    └──────────────────┘   │
                          └─────────────────────────────────────────────┘
                                    ▲           ▲           ▲
                          ┌─────────┘     ┌─────┘     ┌─────┘
                          ▼               ▼           ▼
          ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
          │ certchain-       │  │ certchain-       │  │ certchain-       │
          │ techpulse        │  │ dataforge        │  │ neuralpath       │
          │                  │  │                  │  │                  │
          │ ┌──────────────┐ │  │ ┌──────────────┐ │  │ ┌──────────────┐ │
          │ │ Keycloak     │ │  │ │ Keycloak     │ │  │ │ Keycloak     │ │
          │ │ (org-local)  │ │  │ │ (org-local)  │ │  │ │ (org-local)  │ │
          │ ├──────────────┤ │  │ ├──────────────┤ │  │ ├──────────────┤ │
          │ │ course-      │ │  │ │ course-      │ │  │ │ course-      │ │
          │ │ manager-ui   │ │  │ │ manager-ui   │ │  │ │ manager-ui   │ │
          │ ├──────────────┤ │  │ ├──────────────┤ │  │ ├──────────────┤ │
          │ │ cert-admin-  │ │  │ │ cert-admin-  │ │  │ │ cert-admin-  │ │
          │ │ api          │ │  │ │ api          │ │  │ │ api          │ │
          │ ├──────────────┤ │  │ ├──────────────┤ │  │ ├──────────────┤ │
          │ │ peer0 +      │ │  │ │ peer0 +      │ │  │ │ peer0 +      │ │
          │ │ CouchDB      │ │  │ │ CouchDB      │ │  │ │ CouchDB      │ │
          │ ├──────────────┤ │  │ ├──────────────┤ │  │ ├──────────────┤ │
          │ │ orderer1     │ │  │ │ orderer2     │ │  │ │ orderer3     │ │
          │ │ (BFT member) │ │  │ │ (BFT member) │ │  │ │ (BFT member) │ │
          │ └──────────────┘ │  │ └──────────────┘ │  │ └──────────────┘ │
          └──────────────────┘  └──────────────────┘  └──────────────────┘
```

| Layer | What | Technology |
|---|---|---|
| **Frontend** | Per-org registrar dashboard + central verification portal | React 19, Vite, TailwindCSS, Express |
| **API** | Per-org certificate CRUD + central verification | Quarkus (Java 21) |
| **Identity** | Per-org auth + cross-org student login | Keycloak 26 with Identity Brokering |
| **Blockchain** | Immutable certificate ledger | Hyperledger Fabric 3.1 (4 BFT orderers, 3 peers, CouchDB) |
| **Monitoring** | Metrics collection + dashboards | Prometheus (OpenShift built-in), Grafana Operator |
| **Deployment** | GitOps-driven, multi-namespace | ArgoCD App-of-Apps, Helm, OpenShift |

---

## Hyperledger Fabric Concepts

[Hyperledger Fabric](https://www.hyperledger.org/projects/fabric) is a **permissioned blockchain** — unlike Bitcoin or Ethereum, only authorized organizations can join and write data. This makes it suitable for enterprise use cases where participants are known and governed.

### Key Components

| Component | What it does | In this demo |
|---|---|---|
| **Peer** | Stores the ledger and executes smart contracts (endorsement) | 3 peers — one per org (`peer0-techpulse`, `peer0-dataforge`, `peer0-neuralpath`) |
| **Orderer** | Sequences endorsed transactions into blocks using consensus | 4 orderers using BFT — `orderer0` (central) + one per org |
| **Smart Contract** (Chaincode) | Business logic that validates transactions before they are committed | `certcontract` — validates certificate fields, enforces issuance/revocation rules |
| **Channel** | An isolated ledger shared by a set of organizations | Single channel `certchannel` shared by all 3 orgs |
| **MSP** (Membership Service Provider) | Cryptographic identity for an organization (certificates + signing keys) | One MSP per org: `TechPulseMSP`, `DataForgeMSP`, `NeuralPathMSP` |
| **Fabric CA** | Certificate authority that enrolls peers, orderers, and admins | Shared CA for demo simplicity (production: one per org) |
| **CouchDB** | Rich-query state database that backs each peer's world state | One per peer — enables JSON queries on certificate data |

### Blockchain Network Diagram

This diagram shows **only the Fabric blockchain layer** — no application servers, UIs, or identity providers.

```
                    ┌────────────────────────────────────────────────┐
                    │              BFT Consensus Cluster              │
                    │                                                │
                    │   orderer0        orderer1        orderer2     │
                    │   (central)       (TechPulse)     (DataForge)  │
                    │       │               │               │        │
                    │       │    orderer3    │               │        │
                    │       │  (NeuralPath)  │               │        │
                    │       └───────┼───────┘               │        │
                    │               │                       │        │
                    │       ┌───────┴───────────────────────┘        │
                    │       │     Ordered blocks broadcast           │
                    └───────┼────────────────────────────────────────┘
                            │
            ┌───────────────┼───────────────────────────┐
            │               │                           │
            ▼               ▼                           ▼
   ┌─────────────┐  ┌─────────────┐            ┌─────────────┐
   │   peer0     │  │   peer0     │            │   peer0     │
   │  TechPulse  │  │  DataForge  │            │ NeuralPath  │
   │             │  │             │            │             │
   │ ┌─────────┐ │  │ ┌─────────┐ │            │ ┌─────────┐ │
   │ │ Ledger  │ │  │ │ Ledger  │ │            │ │ Ledger  │ │
   │ │ (full   │ │  │ │ (full   │ │            │ │ (full   │ │
   │ │  copy)  │ │  │ │  copy)  │ │            │ │  copy)  │ │
   │ └─────────┘ │  │ └─────────┘ │            │ └─────────┘ │
   │ ┌─────────┐ │  │ ┌─────────┐ │            │ ┌─────────┐ │
   │ │CouchDB  │ │  │ │CouchDB  │ │            │ │CouchDB  │ │
   │ │(state)  │ │  │ │(state)  │ │            │ │(state)  │ │
   │ └─────────┘ │  │ └─────────┘ │            │ └─────────┘ │
   └──────┬──────┘  └──────┬──────┘            └──────┬──────┘
          │                │                          │
          └────────────────┼──────────────────────────┘
                           │
                  ┌────────┴────────┐
                  │  certcontract   │
                  │  (Go chaincode) │  ← Chaincode-as-a-Service
                  │                 │     (CcaaS)
                  └────────┬────────┘
                           │
                  ┌────────┴────────┐
                  │   Fabric CA     │  ← Enrolls identities for
                  │   (shared)      │     peers, orderers, admins
                  └─────────────────┘
```

### How a Transaction Works

1. **Propose** — A client (e.g., cert-admin-api) sends a transaction proposal to a peer
2. **Endorse** — The peer executes the smart contract and signs the result (endorsement)
3. **Order** — The client sends the endorsed transaction to the orderer cluster
4. **Commit** — Orderers sequence it into a block and broadcast to all peers; each peer validates and commits to its ledger

With **BFT (Byzantine Fault Tolerant) consensus** and 4 orderers (f=1), the network tolerates 1 malicious or unavailable orderer. Read-only queries (like certificate verification) go directly to a peer's local ledger copy — no orderer involvement needed.

---

## Keycloak Identity Architecture

This demo uses [Keycloak](https://www.keycloak.org/) for identity management across multiple organizations. Each org gets full auth isolation, while students get seamless cross-org login via identity brokering.

### Key Concepts

| Concept | What it does | In this demo |
|---|---|---|
| **Realm** | Isolated authentication boundary (users, clients, roles) | `techpulse`, `dataforge`, `neuralpath` realms (one per org KC) + `certchain` realm (central KC) |
| **Client** | An application registered with Keycloak for OIDC auth | `course-manager-ui` (registrar SPA), `cert-admin-api` (API bearer auth), `cert-portal` (student SPA) |
| **Identity Brokering** | Delegating authentication to an external identity provider | Central KC brokers login to org KCs — student authenticates at their org but gets a central token |
| **KC Organizations** | Multi-tenancy feature with email-domain-based routing | Maps `@techpulse.demo` → TechPulse org → auto-redirect to TechPulse KC |
| **JIT Provisioning** | Auto-create user record on first brokered login | Central KC creates a shadow user when a student first logs in via an org KC |

### Identity Flow Diagram

```
  Registrar Login (direct)              Student Login (brokered)
  ─────────────────────────             ────────────────────────────────

  ┌──────────────────┐                  ┌──────────────────┐
  │ course-manager-ui│                  │   cert-portal    │
  │ (TechPulse)      │                  │   (central)      │
  └────────┬─────────┘                  └────────┬─────────┘
           │                                     │
           │ OIDC login                          │ ① Click "Login"
           ▼                                     ▼
  ┌──────────────────┐                  ┌──────────────────┐
  │   Keycloak       │                  │   Keycloak       │
  │   (TechPulse)    │                  │   (Central)      │
  │                  │                  │                  │
  │  techpulse realm │                  │  certchain realm │
  │  • admin users   │                  │  • KC Orgs       │
  │  • org roles     │                  │  • IDP configs   │
  └──────────────────┘                  └────────┬─────────┘
                                                 │
                                                 │ ② Enter email:
                                                 │   student01@techpulse.demo
                                                 │
                                                 │ ③ KC Organizations detects
                                                 │   domain "techpulse.demo"
                                                 │
                                                 │ ④ Auto-redirect (no IDP picker)
                                                 ▼
                                        ┌──────────────────┐
                                        │   Keycloak       │
                                        │   (TechPulse)    │
                                        │                  │
                                        │ ⑤ Student enters │
                                        │   password       │
                                        └────────┬─────────┘
                                                 │
                                                 │ ⑥ Redirect back
                                                 ▼
                                        ┌──────────────────┐
                                        │   Keycloak       │
                                        │   (Central)      │
                                        │                  │
                                        │ ⑦ JIT provision  │
                                        │   user under     │
                                        │   TechPulse Org  │
                                        │                  │
                                        │ ⑧ Issue central  │
                                        │   token → student│
                                        │   sees transcript│
                                        └──────────────────┘
```

**Why this design?** Each org controls its own user directory — a TechPulse admin never exists in DataForge's Keycloak. Students get a single login experience: they enter their email, and Keycloak automatically routes them to the right org. No manual IDP selection menu.

---

<details>
<summary><strong>📖 Background: OpenShift, ArgoCD, and other components</strong></summary>

### Red Hat OpenShift (Container Platform)

Running 3 organizations with 20+ microservices requires container orchestration. OpenShift gives each institute its own **namespace** (isolated environment) with its own identity provider, API, and UI — just like a real multi-tenant SaaS setup. It adds self-healing (crashed pods restart automatically), route management (HTTPS URLs for every service), and built-in container image builds.

### ArgoCD (GitOps)

With 40+ Kubernetes resources across 5 namespaces, manual `oc apply` is error-prone. ArgoCD watches the Git repository and automatically keeps the cluster in sync with the declared Helm charts. The GitOps layout uses the **App-of-Apps** pattern: a root Helm chart (`helm/`) generates 5 ArgoCD Application CRs — one for central services, one per organization, and one for the Showroom lab guide. Each Application points to a component sub-chart under `helm/components/`. The RHDP (Red Hat Demo Platform) injects the cluster domain and API URL at order time, and a `UserInfo` ConfigMap passes service URLs back to the platform.

### API Gateway (Production Advisory)

The verification endpoint is anonymous and public. In a production deployment, you should add an API gateway (such as Red Hat Connectivity Link, Kong, or similar) with rate limiting to prevent abuse. This demo does not include an API gateway to keep the setup lean.

</details>

---

## Repository Structure

```
helm/                              ← Root App-of-Apps chart (ArgoCD entry point)
├── Chart.yaml
├── values.yaml                    ← All config: deployer, gitops, org identities
├── templates/
│   ├── applications.yaml          ← Generates 5 ArgoCD Application CRs
│   └── userinfo.yaml              ← RHDP UserInfo ConfigMap
└── components/
    ├── certchain-central/         ← Central services Helm chart
    │   ├── templates/             ← Fabric CA, orderer0, Keycloak, verify-api, cert-portal, Grafana
    │   └── values.yaml
    ├── certchain-org/             ← Per-org services Helm chart (deployed 3x)
    │   ├── templates/             ← peer, orderer, CouchDB, Keycloak, cert-admin-api, course-manager-ui
    │   ├── values.yaml
    │   └── values-{org}.yaml      ← Org-specific overrides (identity, branding)
    └── certchain-showroom/        ← Antora lab guide Helm chart

apps/                              ← Application source code
├── cert-admin-api/                ← Quarkus API (per-org certificate CRUD)
├── verify-api/                    ← Quarkus API (central verification)
├── course-manager-ui/             ← React + Express (registrar dashboard)
└── cert-portal/                   ← React + Express (verification portal)

showroom/                          ← Antora lab guide (AsciiDoc)
├── site.yml                       ← Antora playbook
└── content/modules/ROOT/pages/    ← Lab guide pages

fabric/                            ← Fabric blockchain configuration
├── chaincode/certcontract/        ← Go smart contract (CcaaS)
├── configtx.yaml                  ← Channel configuration (BFT, 4 orderers)
├── jobs/                          ← K8s Jobs for channel setup and chaincode lifecycle
└── scripts/                       ← In-cluster setup scripts

scripts/                           ← Deployment and management scripts
keycloak/                          ← Realm JSON exports (per-org + central)
```

**Two deployment modes:**

| Mode | Entry point | When to use |
|---|---|---|
| **ArgoCD (RHDP)** | `helm/` root chart → generates ArgoCD Applications | Production, RHDP catalog |
| **Imperative (dev)** | `scripts/deploy-to-openshift.sh` → `helm upgrade --install` | Local development, testing |

---

## Installation on OpenShift

### Prerequisites

| Requirement | Notes |
|---|---|
| OpenShift 4.16+ | Cluster-admin access required |
| `oc` CLI | Logged into the cluster (`oc login ...`) |
| `helm` 3.x | Helm CLI for chart rendering |
| `make`, `curl`, `python3` | Standard dev tools |

### Step 1 — Clone and Configure

```bash
git clone https://github.com/serhat-dirik/hyperledger-on-openshift-demo.git
cd hyperledger-on-openshift-demo
```

Edit `env.sh` if you need to override the container registry or domain suffix. By default, the deploy script auto-detects these from your cluster.

### Step 2 — Verify Cluster Readiness

```bash
./scripts/check-prerequisites.sh
```

This checks: `oc` connectivity, OpenShift version, required operators, resource availability, and tooling. Fix any `[FAIL]` items before proceeding.

### Step 3 — Deploy

```bash
source env.sh
./scripts/deploy-to-openshift.sh
```

This runs 8 steps automatically:
1. Creates 4 namespaces and configures cross-namespace image pull access
2. Creates Keycloak realm ConfigMaps from JSON files
3. Builds container images on-cluster (cert-admin-api, verify-api, course-manager-ui, cert-portal)
4. Installs the `certchain-central` Helm chart (Fabric CA, orderer0, Keycloak, cert-portal, verify-api, Grafana)
5. Installs the `certchain-org` Helm chart per org (peer, orderer, CouchDB, Keycloak, APIs, UIs)
6. Waits for all pods to be ready
7. Sets up Fabric crypto (CA enrollment, MSP/TLS secrets) and cross-namespace networking
8. Verifies all pods and Helm releases

> **Tip:** If images are already built, skip rebuilds: `./scripts/deploy-to-openshift.sh --skip-builds`

### Step 4 — Create Fabric Channel & Deploy Chaincode

After all pods are running and crypto is enrolled, create the channel and deploy the chaincode:

```bash
./scripts/setup-fabric-channel.sh
```

This runs 7 steps:
1. Copies org admin MSP and peer TLS secrets to the central namespace
2. Creates ServiceAccount and RBAC for setup jobs
3. Generates the genesis block locally via `configtxgen` (downloads Fabric binaries if needed)
4. Creates ConfigMaps for channel setup scripts
5. Runs the channel-setup job (joins 4 orderers and 3 peers to `certchannel`)
6. Builds and deploys the chaincode container (CcaaS pattern — `certcontract` at port 7052)
7. Runs the chaincode-lifecycle job (install, approve, commit across all 3 orgs)

> **Note:** The chaincode uses the **Chaincode-as-a-Service (CcaaS)** pattern — it runs as a standalone gRPC service that peers connect to, rather than being managed by the peer process. This enables independent scaling and zero-downtime upgrades.

### Step 5 — Configure Identity Brokering

```bash
./scripts/configure-identity-brokering.sh
```

Sets up the central Keycloak to broker logins to per-org Keycloak instances based on email domain.

### Step 6 — Enable Monitoring

```bash
./scripts/setup-enable-user-workload-monitoring.sh
./scripts/setup-grafana-datasource.sh
```

Enables OpenShift user workload monitoring (Prometheus scraping of ServiceMonitors in user namespaces) and configures Grafana's datasource to query Thanos Querier. Requires cluster-admin.

### Step 7 — Seed Demo Data

```bash
./scripts/seed-demo-certificates.sh
```

Issues 15 sample certificates (5 per org) and verifies them.

### Validation

After deployment, verify everything is working:

```bash
# All pods should be Running and 1/1 Ready
oc get pods -n certchain
oc get pods -n certchain-techpulse
oc get pods -n certchain-dataforge
oc get pods -n certchain-neuralpath

# Check routes are accessible
oc get routes -n certchain
oc get routes -n certchain-techpulse
```

Quick smoke test — verify a seeded certificate:

```bash
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')
curl -sk "https://verify-api-certchain.${DOMAIN}/api/v1/verify/TP-FSWD-001" | python3 -m json.tool
```

Expected output: a JSON object with `"status": "ACTIVE"`.

### Full E2E Validation

Run the automated end-to-end validation suite:

```bash
./scripts/e2e-full-validation.sh --validate
```

This validates 25 checks across 4 phases: pod health (4 namespaces), route accessibility (10 endpoints), API tests (auth, issue, verify, revoke, re-verify), and monitoring stack (ServiceMonitors, Grafana, metrics, UWM pods).

<details>
<summary><strong>E2E validation output (25 pass, 0 fail)</strong></summary>

```
Phase 6: Validate Pod Health
  ✓ PASS — All 9 service pods running in certchain
  ✓ PASS — All 7 service pods running in certchain-techpulse
  ✓ PASS — All 7 service pods running in certchain-dataforge
  ✓ PASS — All 7 service pods running in certchain-neuralpath

Phase 7: Validate Routes & Endpoints
  ✓ PASS — CertChain Portal (HTTP 200)
  ✓ PASS — Verify API health (HTTP 200)
  ✓ PASS — TechPulse Course Manager (HTTP 200)
  ✓ PASS — TechPulse cert-admin-api health (HTTP 200)
  ✓ PASS — DataForge cert-admin-api health (HTTP 200)
  ✓ PASS — NeuralPath cert-admin-api health (HTTP 200)
  ✓ PASS — Central Keycloak (HTTP 200)
  ✓ PASS — TechPulse Keycloak (HTTP 200)
  ✓ PASS — DataForge Keycloak (HTTP 200)
  ✓ PASS — NeuralPath Keycloak (HTTP 200)

Phase 8: API Tests — Authentication & Certificate Lifecycle
  ✓ PASS — Keycloak authentication (TechPulse)
  ✓ PASS — Dashboard stats API
  ✓ PASS — Certificate issuance (HTTP 201)
  ✓ PASS — Certificate verification (status: VALID)
  ✓ PASS — Certificate revocation (HTTP 200)
  ✓ PASS — Post-revocation verification (status: REVOKED)
  ⊘ SKIP — Cross-org verification (seeded certs not found)

Phase 9: Validate Monitoring Stack
  ✓ PASS — ServiceMonitors in certchain (2 found)
  ✓ PASS — ServiceMonitors in certchain-techpulse (3 found)
  ✓ PASS — Grafana reachable (HTTP 200)
  ✓ PASS — Custom certificate metrics present
  ✓ PASS — User workload monitoring pods running (5 pods)

Passed: 25  Failed: 0  Skipped: 1
```

</details>

<details>
<summary><strong>Certificate lifecycle test output (issue → verify → revoke → re-verify)</strong></summary>

```json
// 1. Issue certificate
{
    "certID": "DEMO-001",
    "studentName": "Jane Smith",
    "courseName": "Advanced Blockchain",
    "orgName": "TechPulse Academy",
    "status": "ACTIVE",
    "txID": "41ebde98e6e9e1b014a852fa45980892180376c9..."
}

// 2. Verify → VALID
{
    "certID": "DEMO-001",
    "status": "VALID",
    "studentName": "Jane Smith",
    "courseName": "Advanced Blockchain",
    "orgName": "TechPulse Academy"
}

// 3. Revoke
{
    "certID": "DEMO-001",
    "status": "REVOKED",
    "revokeReason": "Demo revocation test"
}

// 4. Re-verify → REVOKED
{
    "certID": "DEMO-001",
    "status": "REVOKED",
    "revokeReason": "Demo revocation test"
}
```

</details>

<details>
<summary><strong>Pod status across all namespaces</strong></summary>

```
=== certchain (central) ===
cert-portal          1/1   Running
certcontract         1/1   Running     ← Go chaincode (CcaaS)
fabric-ca            1/1   Running
grafana              1/1   Running
grafana-operator     1/1   Running
keycloak             1/1   Running
orderer0             1/1   Running     ← BFT orderer (central)
postgres             1/1   Running
verify-api           1/1   Running

=== certchain-techpulse ===
cert-admin-api       1/1   Running
couchdb              1/1   Running     ← Peer state database
course-manager-ui    1/1   Running
keycloak             1/1   Running     ← Org-local identity provider
orderer              1/1   Running     ← BFT orderer (TechPulse)
peer0                1/1   Running     ← Fabric peer
postgres             1/1   Running

(dataforge and neuralpath: same layout)
```

</details>

### Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| Pods stuck in `Pending` | `oc describe pod <name> -n <ns>` | Cluster may lack resources. Check node capacity. |
| Pods in `CrashLoopBackOff` | `oc logs <pod> -n <ns>` | Usually a config issue. Check env vars and ConfigMaps. |
| Build fails | `oc get builds -n certchain` | Check build logs: `oc logs build/<name> -n certchain` |
| Keycloak not starting | `oc logs <kc-pod> -n <ns>` | Postgres may not be ready. Check PG pod first. |
| `curl` to route returns 503 | `oc get pods -n <ns>` | Pod may still be starting. Wait 30s and retry. |
| Identity brokering not working | Central KC admin console → Identity Providers | Run `./scripts/configure-identity-brokering.sh` again. |
| Seed data fails | Script output shows HTTP codes | Keycloak or API pods may not be ready. Wait and retry. |
| Channel setup job fails | `oc logs job/fabric-channel-setup -n certchain` | Orderers/peers may not be ready. Delete job and re-run. |
| Chaincode `CORE_CHAINCODE_ID_NAME` error | `oc logs deploy/certcontract -n certchain` | Check ConfigMap `chaincode-id` exists: `oc get cm chaincode-id -n certchain` |
| verify-api TLS handshake fails | `oc logs deploy/verify-api -n certchain` | Use FQDN for `FABRIC_PEER_ENDPOINT` (e.g., `peer0.certchain-techpulse.svc.cluster.local:7051`) |
| Grafana Operator not installing | `oc get csv -n certchain` | Install Grafana Operator via OLM: `oc apply -f helm/components/certchain-central/templates/grafana/` |

---

## Demo Walkthrough — End User

This is a manual, step-by-step guide. Open the URLs in your browser and follow along.

> **Find your domain:** `oc get ingresses.config cluster -o jsonpath='{.spec.domain}'`
>
> All URLs below use `${DOMAIN}` as a placeholder. Replace it with your actual domain.

### Demo Users

| Role | Login URL | Username | Password |
|---|---|---|---|
| **ArgoCD Admin** | `https://openshift-gitops-server-openshift-gitops.${DOMAIN}` | `admin` | `admin` |
| TechPulse Registrar | `https://course-manager-ui-certchain-techpulse.${DOMAIN}` | `admin@techpulse.demo` | `admin` |
| DataForge Registrar | `https://course-manager-ui-certchain-dataforge.${DOMAIN}` | `admin@dataforge.demo` | `admin` |
| NeuralPath Registrar | `https://course-manager-ui-certchain-neuralpath.${DOMAIN}` | `admin@neuralpath.demo` | `admin` |
| Student (TechPulse) | `https://cert-portal-certchain.${DOMAIN}` | `student01@techpulse.demo` | `student` |
| Student (DataForge) | `https://cert-portal-certchain.${DOMAIN}` | `student03@dataforge.demo` | `student` |
| Student (NeuralPath) | `https://cert-portal-certchain.${DOMAIN}` | `student05@neuralpath.demo` | `student` |

> **Tip:** ArgoCD also accepts **Log in via OpenShift** — any user in the `cluster-admins` group gets admin access automatically.

---

### Step 1 — Registrar Issues a Certificate

**Who:** You are a TechPulse Academy registrar.

1. Open **TechPulse Course Manager**: `https://course-manager-ui-certchain-techpulse.${DOMAIN}`
2. Log in with `admin@techpulse.demo` / `admin`
3. You land on the **Dashboard** — it shows certificate statistics (total, active, revoked)

   <!-- ![Course Manager Dashboard](media/screenshots/course-manager-dashboard.png) -->

4. Click **"Issue Certificate"** in the navigation
5. Fill in the form:
   - Select a course (e.g., "Full-Stack Web Dev")
   - Enter student name and ID
   - Set issue and expiry dates
6. Click **Submit**
7. **What happened:** The certificate was written to the Hyperledger Fabric ledger via TechPulse's peer. You should see a success message with a certificate ID.
8. Copy the **certificate ID** — you will need it for the next step.

---

### Step 2 — Employer Verifies a Certificate (Anonymous)

**Who:** You are an employer who received a certificate ID from a job applicant.

1. Open **CertChain Portal**: `https://cert-portal-certchain.${DOMAIN}`
2. You do **not** need to log in — verification is anonymous
3. Enter the certificate ID from Step 1 (or use a seeded one: `TP-FSWD-001`)
4. Click **Verify**
5. **What you see** (public info only):
   - ✅ **ACTIVE** status (green)
   - Student name, course name, issuing organization
   - Issue and expiry dates

   <!-- ![Certificate Verification — VALID](media/screenshots/cert-portal-valid.png) -->

6. **What you don't see:** Grade and degree — these private fields are only visible to the certificate owner when logged in. This privacy enforcement is server-side (verify-api strips private fields from anonymous responses).

> **Alternative:** If the cert-portal has QR scanning enabled, you can also scan a QR code instead of typing the ID.

---

### Step 3 — Student Views Their Transcript (Identity Brokering)

**Who:** You are Alice Chen, a TechPulse student.

1. Open **CertChain Portal**: `https://cert-portal-certchain.${DOMAIN}`
2. Click **"Login"** (top-right)
3. You are redirected to the **Central Keycloak** login page
4. Enter email: `student01@techpulse.demo`
5. **What happens behind the scenes:**
   - Central Keycloak detects the `@techpulse.demo` domain
   - It automatically redirects you to **TechPulse's Keycloak** — no manual IDP selection
6. Enter password: `student`
7. You are redirected back to the CertChain Portal, now authenticated
8. Click **"My Transcript"**
9. **What you see:** All certificates issued to you across all institutes
   - **Your own certificates:** Full details including grade and degree (private fields)
   - **Other students' certificates:** Only public info (grade/degree hidden)
   - This ownership-based privacy is enforced server-side by matching the JWT email claim against the certificate's studentID

   <!-- ![Student Transcript](media/screenshots/cert-portal-transcript.png) -->

---

### Step 4 — Registrar Revokes a Certificate

**Who:** You are the TechPulse registrar again.

1. Go back to **TechPulse Course Manager**: `https://course-manager-ui-certchain-techpulse.${DOMAIN}`
2. Navigate to **Certificate List**
3. Find the certificate you issued in Step 1
4. Click on it to view details
5. Click **"Revoke"**
6. Enter a reason (e.g., "Academic policy violation")
7. Confirm the revocation
8. **What happened:** A revocation transaction was written to the Fabric ledger. This is **permanent** — the certificate can never be un-revoked.

---

### Step 5 — Employer Re-verifies (Sees Revoked)

**Who:** You are the employer again.

1. Go back to **CertChain Portal**: `https://cert-portal-certchain.${DOMAIN}`
2. Enter the **same certificate ID** from Step 1
3. Click **Verify**
4. **What you see:**
   - ❌ **REVOKED** status (red)
   - The revocation reason
   - The original certificate details are still visible for reference

   <!-- ![Certificate Verification — REVOKED](media/screenshots/cert-portal-revoked.png) -->

---

### Step 6 — Try Another Org

Repeat Steps 1–5 with **DataForge Institute** to see that each org is fully independent:

- DataForge Course Manager: `https://course-manager-ui-certchain-dataforge.${DOMAIN}`
- Login: `admin@dataforge.demo` / `admin`
- Student: `student03@dataforge.demo` / `student`

Note that each org's certificates are isolated — a TechPulse registrar cannot see or revoke DataForge certificates.

---

## Demo Walkthrough — Resilience & Self-Healing

This walkthrough demonstrates OpenShift and blockchain resilience. Run the scripted version or follow the manual steps.

**Scripted (recommended):**

```bash
./scripts/resilience-demo.sh
```

**Manual walkthrough:**

### Part 1 — Pod Self-Healing

**What you show:** Kubernetes automatically restarts failed containers.

1. Open a terminal and watch pods: `oc get pods -n certchain-techpulse -w`
2. In another terminal, kill TechPulse's CouchDB: `oc delete pod -l app=couchdb -n certchain-techpulse --force`
3. Watch the first terminal — a new pod is created within seconds
4. Within 10–30 seconds, the pod is back to `Running 1/1`
5. **Point to make:** No manual intervention needed. Deployments declare the desired state, OpenShift enforces it.

### Part 2 — Multi-Org Isolation

**What you show:** One org's failure doesn't affect other orgs.

1. Kill TechPulse's cert-admin-api: `oc delete pod -l app=cert-admin-api -n certchain-techpulse --force`
2. Immediately test DataForge: `curl -sk "https://cert-admin-api-certchain-dataforge.${DOMAIN}/q/health/ready"` → HTTP 200
3. Also verify NeuralPath: `curl -sk "https://cert-admin-api-certchain-neuralpath.${DOMAIN}/q/health/ready"` → HTTP 200
4. TechPulse recovers on its own within 30 seconds
5. **Point to make:** Namespace isolation means one org's outage is invisible to others.

### Part 3 — Blockchain Decentralization

**What you show:** Certificate verification survives central infrastructure failure.

1. Verify a cert via central: `curl -sk "https://verify-api-certchain.${DOMAIN}/api/v1/verify/TP-FSWD-001"` → VALID
2. **Kill central services:** `oc -n certchain scale deployment orderer0 verify-api --replicas=0`
3. Central verify-api is now unreachable (503)
4. Verify the **same cert** via TechPulse's local verify-api: `curl -sk "https://verify-api-certchain-techpulse.${DOMAIN}/api/v1/verify/TP-FSWD-001"` → **Still VALID!**
5. **Explain why:** Each peer holds a full copy of the ledger. Verification is a read-only query — it doesn't need the orderer. Only write operations (issue/revoke) require consensus.
6. Restore: `oc -n certchain scale deployment orderer0 verify-api --replicas=1`

---

## Demo Walkthrough — Monitoring & Observability

This walkthrough demonstrates the observability stack. Run the scripted version or follow the manual steps.

**Scripted (recommended):**

```bash
./scripts/demo-monitoring-walkthrough.sh
```

**Manual walkthrough:**

### Part 1 — Prometheus Metrics from Fabric

1. Exec into a peer pod to see raw Prometheus metrics:
   ```bash
   oc exec -n certchain-techpulse deploy/peer0 -- wget -qO- http://localhost:9443/metrics | head -30
   ```
2. Look for key Fabric metrics:
   - `endorser_proposals_received` — proposals this peer has processed
   - `ledger_blockstorage_commit_time` — block commit latency
   - `grpc_server_active_streams` — active gRPC connections

3. Same for an orderer:
   ```bash
   oc exec -n certchain deploy/orderer0 -- wget -qO- http://localhost:8443/metrics | grep consensus
   ```

### Part 2 — Quarkus Application Metrics

1. Hit the cert-admin-api metrics endpoint (publicly accessible):
   ```bash
   curl -sk "https://cert-admin-api-certchain-techpulse.${DOMAIN}/q/metrics" | grep certificate_
   ```
2. You should see custom counters:
   - `certificate_issued_total` — number of certificates issued
   - `certificate_revoked_total` — number of certificates revoked

3. Issue a certificate and watch the counter increment:
   ```bash
   # Check counter before
   curl -sk "https://cert-admin-api-certchain-techpulse.${DOMAIN}/q/metrics" | grep certificate_issued
   # Issue a cert (use the demo-walkthrough or seed script)
   # Check counter after — should have incremented
   ```

4. Same for verify-api:
   ```bash
   curl -sk "https://verify-api-certchain.${DOMAIN}/q/metrics" | grep certificate_
   ```
   - `certificate_verified_total` — successful verifications
   - `certificate_not_found_total` — lookup misses

### Part 3 — OpenShift Console Metrics

1. Open the OpenShift Console → **Observe → Metrics**
2. Try these PromQL queries:
   - `rate(endorser_proposals_received[5m])` — peer endorsement rate
   - `certificate_issued_total` — certificates issued per org
   - `rate(http_server_requests_seconds_count{job=~".*cert-admin-api.*"}[5m])` — API request rate
3. Navigate to **Observe → Targets** — see all ServiceMonitor targets and their scrape health

### Part 4 — Grafana Dashboards

1. Get the Grafana URL:
   ```bash
   oc get route -n certchain -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].spec.host}'
   ```
2. Open in browser. Login: `admin` / `certchain`
3. Navigate to **Dashboards** and explore the three pre-configured dashboards:
   - **CertChain — Fabric Network:** Peer endorsement rates, block commit latency, orderer consensus, gRPC connections
   - **CertChain — Application APIs:** Certificate operation counters (issued/revoked/verified), HTTP request rates and p99 latency, JVM heap and GC metrics
   - **CertChain — Infrastructure Health:** Pod CPU/memory usage, PVC capacity, restart counts, network I/O
4. **Generate activity** by running `./scripts/seed-demo-certificates.sh` and watch the dashboards update in real-time

<!-- ![Grafana — Fabric Network Dashboard](media/screenshots/grafana-fabric.png) -->

---

## Admin & Management Guide

This section is for platform operators and demo administrators. All steps are manual.

### Check Cluster Health

```bash
# Are all pods running?
for ns in certchain certchain-techpulse certchain-dataforge certchain-neuralpath; do
  echo "=== $ns ==="
  oc get pods -n $ns
  echo
done
```

Every pod should show `1/1 Running`. If any pod shows `0/1` or `CrashLoopBackOff`, check its logs:

```bash
oc logs <pod-name> -n <namespace>
```

### Check Routes & URLs

```bash
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')
echo "CertChain Portal:       https://cert-portal-certchain.${DOMAIN}"
echo "Verify API (Swagger):   https://verify-api-certchain.${DOMAIN}/q/swagger-ui"
echo "Central Keycloak:       https://keycloak-certchain.${DOMAIN}"
echo ""
echo "TechPulse Course Mgr:   https://course-manager-ui-certchain-techpulse.${DOMAIN}"
echo "TechPulse Admin API:    https://cert-admin-api-certchain-techpulse.${DOMAIN}/q/swagger-ui"
echo "TechPulse Keycloak:     https://keycloak-certchain-techpulse.${DOMAIN}"
```

Open each URL in a browser. All should load without errors.

### ArgoCD Console

| URL | Username | Password |
|---|---|---|
| `https://openshift-gitops-server-openshift-gitops.${DOMAIN}` | `admin` | `admin` |

You can also click **Log in via OpenShift** — cluster-admin users are auto-mapped to ArgoCD admin role.

### Keycloak Admin Consoles

| Instance | URL | Username | Password |
|---|---|---|---|
| Central | `https://keycloak-certchain.${DOMAIN}` | admin | admin |
| TechPulse | `https://keycloak-certchain-techpulse.${DOMAIN}` | admin | admin |
| DataForge | `https://keycloak-certchain-dataforge.${DOMAIN}` | admin | admin |
| NeuralPath | `https://keycloak-certchain-neuralpath.${DOMAIN}` | admin | admin |

**What to check in each Keycloak:**
1. Log into the admin console
2. Go to **Users** — verify registrar and student accounts exist
3. Go to **Clients** — verify `course-manager-ui` and `cert-admin-api` clients are configured
4. In Central KC: go to **Identity Providers** — verify the 3 org IDPs are configured
5. In Central KC: go to **Organizations** — verify TechPulse, DataForge, NeuralPath orgs exist

### Test the APIs Directly

**Get a Keycloak token:**

```bash
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')

# Get TechPulse admin token
TOKEN=$(curl -sk "https://keycloak-certchain-techpulse.${DOMAIN}/realms/techpulse/protocol/openid-connect/token" \
  -d "client_id=course-manager-ui" \
  -d "username=admin@techpulse.demo" \
  -d "password=admin" \
  -d "grant_type=password" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

**Test cert-admin-api (TechPulse):**

```bash
# View dashboard stats
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://cert-admin-api-certchain-techpulse.${DOMAIN}/api/v1/dashboard/stats" | python3 -m json.tool

# List certificates
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://cert-admin-api-certchain-techpulse.${DOMAIN}/api/v1/certificates" | python3 -m json.tool
```

**Test verify-api (public, no token needed):**

```bash
# Verify a seeded certificate (public — no grade/degree in response)
curl -sk "https://verify-api-certchain.${DOMAIN}/api/v1/verify/TP-FSWD-001" | python3 -m json.tool
```

Expected: `"status": "ACTIVE"` with student, course, and org details (grade and degree omitted for anonymous requests).

**Test student transcript (requires central Keycloak token):**

```bash
# Get a student token via central Keycloak (identity brokering)
STUDENT_TOKEN=$(curl -sk "https://keycloak-certchain.${DOMAIN}/realms/certchain/protocol/openid-connect/token" \
  -d "client_id=cert-portal" \
  -d "username=student01@techpulse.demo" \
  -d "password=student" \
  -d "grant_type=password" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# View transcript — shows grade/degree only on the student's own certificates
curl -sk -H "Authorization: Bearer $STUDENT_TOKEN" \
  "https://verify-api-certchain.${DOMAIN}/api/v1/transcript" | python3 -m json.tool
```

### Monitoring & Observability

The demo includes a full observability stack using OpenShift's built-in Prometheus and Grafana Operator.

**Metrics sources:**

| Component | Port | Path | Metrics |
|---|---|---|---|
| Fabric peers | 9443 | `/metrics` | Endorsements, block commits, gRPC streams |
| Fabric orderers | 8443 | `/metrics` | Consensus, block cuts, broadcast latency |
| cert-admin-api | 8080 | `/q/metrics` | `certificate.issued`, `certificate.revoked`, HTTP, JVM |
| verify-api | 8080 | `/q/metrics` | `certificate.verified`, `certificate.not_found`, HTTP, JVM |

**Grafana dashboards** (3 pre-configured):

| Dashboard | What it shows |
|---|---|
| **CertChain — Fabric Network** | Peer proposals, block commit latency, orderer consensus, gRPC connections |
| **CertChain — Application APIs** | Certificate operation counters, HTTP request rates, p99 latency, JVM heap/GC |
| **CertChain — Infrastructure Health** | Pod CPU/memory, PVC usage, restart counts, network I/O |

**Access Grafana:**

```bash
# Get the Grafana URL
oc get route -n certchain -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].spec.host}'
# Login: admin / certchain
```

**Run the interactive monitoring walkthrough:**

```bash
./scripts/demo-monitoring-walkthrough.sh
```

This walks through all 3 layers: Fabric metrics, application counters, and Grafana dashboards.

**Query metrics directly in OpenShift Console:**

Navigate to **Observe → Metrics** and try:
- `rate(endorser_proposals_received[5m])` — peer endorsement rate
- `certificate_issued_total` — certificates issued per org
- `http_server_requests_seconds_count{job=~".*cert-admin-api.*"}` — API request counts

**Check Fabric peer and orderer health:**

```bash
# Peer pods (one per org)
oc get pods -l app=peer -n certchain-techpulse
oc get pods -l app=peer -n certchain-dataforge
oc get pods -l app=peer -n certchain-neuralpath

# Chaincode pod (runs the smart contract)
oc get pods -l app=certcontract -n certchain

# ServiceMonitors
oc get servicemonitors -n certchain
oc get servicemonitors -n certchain-techpulse
```

### Scale and Resilience Testing

Run the full interactive resilience demo:

```bash
./scripts/resilience-demo.sh
```

This covers 3 scenarios automatically. You can also run them manually:

**Scenario 1 — Pod Self-Healing:**

```bash
# Kill the TechPulse CouchDB pod
oc delete pod -l app=couchdb -n certchain-techpulse --grace-period=0 --force

# Watch Kubernetes auto-restart it (usually 10-30 seconds)
oc get pods -n certchain-techpulse -w
```

**Scenario 2 — Multi-Org Isolation:**

```bash
# Kill TechPulse's cert-admin-api
oc delete pod -l app=cert-admin-api -n certchain-techpulse --grace-period=0 --force

# DataForge should be completely unaffected
curl -sk "https://cert-admin-api-certchain-dataforge.${DOMAIN}/q/health/ready"
# → HTTP 200 (DataForge still works while TechPulse recovers)
```

**Scenario 3 — Blockchain Decentralization (Chain Resilience):**

This demonstrates the core blockchain value: certificate verification works even when central services are offline, because each peer holds a full copy of the ledger.

```bash
# Stop central orderer and verify-api
oc -n certchain scale deployment orderer0 --replicas=0
oc -n certchain scale deployment verify-api --replicas=0

# Central verify-api is now DOWN
curl -sk "https://verify-api-certchain.${DOMAIN}/api/v1/verify/TP-FSWD-001"
# → Connection refused / 503

# But TechPulse's local verify-api STILL WORKS (reads from local peer)
curl -sk "https://verify-api-certchain-techpulse.${DOMAIN}/api/v1/verify/TP-FSWD-001" | python3 -m json.tool
# → HTTP 200, "status": "VALID"

# Restore central services
oc -n certchain scale deployment orderer0 --replicas=1
oc -n certchain scale deployment verify-api --replicas=1
```

Key takeaways:
- Only **write** operations (issue/revoke) need the orderer
- **Read** operations (verify) work from any org's local peer
- Each namespace is independently recoverable

### Swagger UI

Both APIs expose interactive Swagger UI for direct testing:

- **cert-admin-api:** `https://cert-admin-api-certchain-techpulse.${DOMAIN}/q/swagger-ui` (requires Bearer token)
- **verify-api:** `https://verify-api-certchain.${DOMAIN}/q/swagger-ui` (public endpoints, no auth)

To use secured endpoints in Swagger UI: click **Authorize**, paste the Bearer token from the curl command above.

### Teardown

Remove the entire demo from the cluster:

```bash
./scripts/teardown-all.sh
```

This deletes all 4 namespaces and their resources.

---

## Scripts Reference

| Script | Purpose |
|---|---|
| `scripts/setup-all.sh` | Full bootstrap (detect domain, check prereqs, create namespace, enable monitoring) |
| `scripts/deploy-to-openshift.sh` | Deploy all services to OpenShift (7 steps) |
| `scripts/setup-fabric-channel.sh` | Create Fabric channel, deploy chaincode, run lifecycle (install/approve/commit) |
| `scripts/setup-central-fabric.sh` | Enroll central Fabric CA identities and generate crypto |
| `scripts/setup-org-fabric.sh` | Enroll per-org identities (peer, orderer, admin) |
| `scripts/check-prerequisites.sh` | Verify cluster readiness |
| `scripts/configure-identity-brokering.sh` | Set up cross-org login via Keycloak |
| `scripts/seed-demo-certificates.sh` | Issue 15 sample certificates |
| `scripts/setup-enable-user-workload-monitoring.sh` | Enable OpenShift user workload monitoring |
| `scripts/setup-grafana-datasource.sh` | Configure Grafana's Prometheus datasource |
| `scripts/demo-monitoring-walkthrough.sh` | Interactive monitoring demo (7 steps) |
| `scripts/demo-walkthrough.sh` | Interactive end-to-end demo (7 steps: issue, verify, privacy, revoke) |
| `scripts/resilience-demo.sh` | Pod self-healing and failover demo |
| `scripts/test-end-to-end.sh` | Multi-org E2E tests (10 tests: auth, CRUD, cross-org, admin role, ownership privacy) |
| `scripts/e2e-full-validation.sh` | Automated E2E validation (25+ checks across 4 phases) |
| `scripts/teardown-all.sh` | Remove everything from the cluster |

---

## Version Management

All versions are centralized in `env.sh`. Update a variable, rebuild, and ArgoCD auto-rolls the deployment.

## Resource Requirements

Demo-sized: ~6 vCPU, ~7 GB RAM total across all components. See `env.sh` for per-component limits.

## License

Apache License 2.0
