# Hyperledger Fabric on OpenShift — CertChain Demo

> A multi-org blockchain demo running **Hyperledger Fabric 3.1** with BFT consensus,
> per-org Keycloak identity, and GitOps deployment on **Red Hat OpenShift**.

This project demonstrates how to deploy and operate a [Hyperledger Fabric](https://www.hyperledger.org/projects/fabric) permissioned blockchain network on OpenShift. It covers multi-organization governance with BFT consensus, per-org identity isolation via Keycloak, GitOps-driven deployment with ArgoCD, and a full observability stack. **CertChain** — a certificate credentialing system — is the sample use case that ties it all together.

---

## What Does This Demo Show?

- **Hyperledger Fabric 3.1** multi-org network with 4 BFT orderers, 3 peers, and CouchDB state databases
- **Per-org namespace isolation** — each organization gets its own Keycloak, APIs, UI, and blockchain peer
- **Observability** — Prometheus metrics from Fabric and Quarkus, Grafana dashboards
- **Resilience** — pod self-healing, multi-org isolation, blockchain decentralization
- **Certificate ownership privacy** — grade and degree visible only to the certificate owner; public verification shows status and basic info only

### The Demo Scenario

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
| **Student** | Views their full transcript (sees grade/degree only on their own certificates) | Yes — auto-routed to their institute's login |

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
                     ┌───────────────────────────────────────────┐
                     │         certchain  (central)              │
                     │                                           │
                     │  ┌──────────────┐   ┌─────────────────┐   │
                     │  │ Keycloak     │   │ cert-portal     │   │
                     │  │ (central)    │   │ (React PWA)     │   │
                     │  │ • ID broker  │   │ • Verify certs  │   │
                     │  │ • Org route  │   │ • QR scanner    │   │
                     │  └──────────────┘   │ • Transcripts   │   │
                     │                     └───────┬─────────┘   │
                     │  ┌──────────────┐   ┌──────┴──────────┐   │
                     │  │ orderer0     │   │ verify-api      │   │
                     │  │ (BFT)        │   │ (Quarkus)       │   │
                     │  └──────────────┘   └─────────────────┘   │
                     │  ┌──────────────┐                         │
                     │  │ fabric-ca    │   Consortium operator   │
                     │  │ (PKI)        │   (not a Fabric org)    │
                     │  └──────────────┘                         │
                     └───────────────────────────────────────────┘
                               ▲           ▲           ▲
                     ┌─────────┘     ┌─────┘     ┌─────┘
                     ▼               ▼           ▼
     ┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐
     │ certchain-         │ │ certchain-         │ │ certchain-         │
     │ techpulse          │ │ dataforge          │ │ neuralpath         │
     │                    │ │                    │ │                    │
     │ ┌────────────────┐ │ │ ┌────────────────┐ │ │ ┌────────────────┐ │
     │ │ Keycloak       │ │ │ │ Keycloak       │ │ │ │ Keycloak       │ │
     │ │ (org-local)    │ │ │ │ (org-local)    │ │ │ │ (org-local)    │ │
     │ ├────────────────┤ │ │ ├────────────────┤ │ │ ├────────────────┤ │
     │ │ course-        │ │ │ │ course-        │ │ │ │ course-        │ │
     │ │ manager-ui     │ │ │ │ manager-ui     │ │ │ │ manager-ui     │ │
     │ ├────────────────┤ │ │ ├────────────────┤ │ │ ├────────────────┤ │
     │ │ cert-admin-api │ │ │ │ cert-admin-api │ │ │ │ cert-admin-api │ │
     │ ├────────────────┤ │ │ ├────────────────┤ │ │ ├────────────────┤ │
     │ │ certcontract   │ │ │ │ certcontract   │ │ │ │ certcontract   │ │
     │ │ (CcaaS)        │ │ │ │ (CcaaS)        │ │ │ │ (CcaaS)        │ │
     │ ├────────────────┤ │ │ ├────────────────┤ │ │ ├────────────────┤ │
     │ │ peer0 + CouchDB│ │ │ │ peer0 + CouchDB│ │ │ │ peer0 + CouchDB│ │
     │ ├────────────────┤ │ │ ├────────────────┤ │ │ ├────────────────┤ │
     │ │ orderer1       │ │ │ │ orderer2       │ │ │ │ orderer3       │ │
     │ │ (BFT member)   │ │ │ │ (BFT member)   │ │ │ │ (BFT member)   │ │
     │ └────────────────┘ │ │ └────────────────┘ │ │ └────────────────┘ │
     └────────────────────┘ └────────────────────┘ └────────────────────┘
```

| Layer | What | Technology |
|---|---|---|
| **Frontend** | Per-org registrar dashboard + central verification portal | React 19, Vite, TailwindCSS, Express |
| **API** | Per-org certificate CRUD + central verification | Quarkus (Java 21) |
| **Identity** | Per-org auth + cross-org student login | Keycloak 26 with Identity Brokering |
| **Blockchain** | Immutable certificate ledger | Hyperledger Fabric 3.1 (4 BFT orderers, 3 peers, CouchDB, per-org CcaaS) |
| **Monitoring** | Metrics collection + dashboards | Prometheus (OpenShift built-in), Grafana Operator |
| **Deployment** | GitOps-driven, multi-namespace | ArgoCD App-of-Apps, Helm, OpenShift |

---

<details>
<summary><strong>📖 Hyperledger Fabric Concepts</strong></summary>

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
                  ┌──────────────────────────────────────────────┐
                  │             BFT Consensus Cluster            │
                  │                                              │
                  │  orderer0       orderer1       orderer2      │
                  │  (central)      (TechPulse)    (DataForge)   │
                  │      │              │              │         │
                  │      │  orderer3    │              │         │
                  │      │ (NeuralPath) │              │         │
                  │      └──────┼───────┘              │         │
                  │             │                      │         │
                  │      ┌──────┴──────────────────────┘         │
                  │      │    Ordered blocks broadcast           │
                  └──────┼───────────────────────────────────────┘
                         │
           ┌─────────────┼──────────────────────────┐
           │             │                          │
           ▼             ▼                          ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
   │  TechPulse   │ │  DataForge   │ │  NeuralPath  │
   │              │ │              │ │              │
   │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │
   │ │ peer0    │ │ │ │ peer0    │ │ │ │ peer0    │ │
   │ │ Ledger   │ │ │ │ Ledger   │ │ │ │ Ledger   │ │
   │ │ (full)   │ │ │ │ (full)   │ │ │ │ (full)   │ │
   │ ├──────────┤ │ │ ├──────────┤ │ │ ├──────────┤ │
   │ │ CouchDB  │ │ │ │ CouchDB  │ │ │ │ CouchDB  │ │
   │ │ (state)  │ │ │ │ (state)  │ │ │ │ (state)  │ │
   │ ├──────────┤ │ │ ├──────────┤ │ │ ├──────────┤ │
   │ │certcon-  │ │ │ │certcon-  │ │ │ │certcon-  │ │
   │ │tract     │ │ │ │tract     │ │ │ │tract     │ │
   │ │(CcaaS)   │ │ │ │(CcaaS)   │ │ │ │(CcaaS)   │ │
   │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │
   └──────────────┘ └──────────────┘ └──────────────┘

         Each org runs its own chaincode instance.
         All instances use the same sealed image
         for deterministic endorsement.

                  ┌─────────────────┐
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

</details>

<details>
<summary><strong>🔐 Keycloak Identity Architecture</strong></summary>

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

</details>

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

<details>
<summary><strong>📂 Repository Structure</strong></summary>

```
helm/
├── bootstrap/                     ← Phase 1: Bootstrap chart (RHDP / install.sh entry point)
│   ├── values.yaml                ← Deployer config, Gitea toggle, org definitions
│   └── templates/
│       ├── gitea.yaml             ← Local Gitea git server (wave 0)
│       ├── mirror-job.yaml        ← Clone GitHub → Gitea (wave 1)
│       └── applications.yaml      ← Creates 5 ArgoCD Applications (wave 2)
│
└── components/                    ← Phase 2: Deployed by ArgoCD from Gitea (or your fork)
    ├── certchain-central/         ← Central: Fabric CA, orderer0, Keycloak, verify-api, cert-portal, Grafana
    ├── certchain-org/             ← Per-org (deployed 3×): peer, orderer, CouchDB, APIs, UI, Keycloak
    └── certchain-showroom/        ← Lab guide: Antora + terminal + 8 browser tabs

apps/
├── cert-admin-api/                ← Quarkus (Java 21) — per-org certificate CRUD
├── verify-api/                    ← Quarkus (Java 21) — central verification + transcripts
├── course-manager-ui/             ← React + Vite + Express — registrar dashboard
└── cert-portal/                   ← React + Vite + Express — verification portal + QR scanner

fabric/
├── chaincode/certcontract/        ← Go smart contract (CcaaS)
├── configtx.yaml                  ← BFT channel config (4 orderers, 3 orgs)
├── jobs/                          ← K8s Jobs: channel setup, chaincode lifecycle
└── scripts/                       ← In-cluster Fabric setup scripts

showroom/                          ← Antora lab guide (AsciiDoc)
├── site.yml                       ← Playbook + 8 browser tabs config
└── content/modules/ROOT/pages/    ← Walkthrough pages

scripts/                           ← Deployment and management scripts
├── install.sh                     ← BYO cluster installer (--repo-url or --gitea)
├── deploy-to-openshift.sh         ← Imperative deploy (dev/debug)
├── setup-fabric-channel.sh        ← Channel + chaincode lifecycle
├── configure-identity-brokering.sh
├── seed-demo-certificates.sh
└── teardown-all.sh

keycloak/                          ← Realm JSON exports (per-org + central)
```

</details>

---

## Installation on OpenShift

**How deployment works (two phases):**

The bootstrap chart installs a local Gitea server, mirrors this GitHub repo into it, then creates ArgoCD Applications that deploy CertChain from the local Gitea. This gives workshop participants a writable repo — they can push changes (like adding a new org) and ArgoCD auto-syncs.

```
Phase 1 (from GitHub):  bootstrap → Gitea + mirror + ArgoCD Applications
Phase 2 (from Gitea):   certchain-central, 3× org, showroom
```

### Option A — Red Hat Demo Platform (RHDP)

If you have RHDP access, use the **Field Sourced Content** catalog item:

1. Order from RHDP catalog with these parameters:
   - **GitOps Repo URL:** `https://github.com/serhat-dirik/hyperledger-on-openshift-demo.git`
   - **GitOps Path:** `helm/bootstrap`
   - **GitOps Revision:** `main`

2. RHDP provisions the cluster, installs ArgoCD, and creates the root Application. The bootstrap chart automatically:
   - Deploys Gitea and mirrors this repo
   - Creates 5 ArgoCD Applications (central, 3 orgs, showroom)
   - Deploys the full CertChain platform

3. When deployment completes, open the **Showroom** lab guide URL (provided in RHDP order details). The Showroom has interactive walkthroughs with a built-in terminal, OpenShift Console, and Git repo tabs.

### Option B — Bring Your Own Cluster

For any OpenShift 4.16+ cluster with cluster-admin access.

**Prerequisites:** `oc` CLI logged into the cluster.

**Option B1 — With Gitea (recommended for workshops):**

```bash
git clone https://github.com/serhat-dirik/hyperledger-on-openshift-demo.git
cd hyperledger-on-openshift-demo
./scripts/install.sh --gitea
```

This installs a local Gitea, mirrors the repo, and deploys everything via ArgoCD. Workshop participants get a writable repo for hands-on exercises.

**Option B2 — With your own fork:**

Fork this repo to your own GitHub/GitLab, then:

```bash
./scripts/install.sh --repo-url https://github.com/YOUR_USER/hyperledger-on-openshift-demo.git
```

ArgoCD deploys directly from your fork. You can push changes and ArgoCD auto-syncs.

**What the install script does:**

1. Verifies prerequisites (oc login, cluster-admin, OpenShift 4.16+)
2. Auto-detects cluster domain and API URL
3. Ensures OpenShift GitOps (ArgoCD) is installed
4. Creates the root ArgoCD Application pointing to `helm/bootstrap`
5. Waits for bootstrap sync and prints summary URLs

**Post-deploy steps** (run after all pods are ready):

```bash
./scripts/configure-identity-brokering.sh    # Cross-org student login
./scripts/setup-enable-user-workload-monitoring.sh  # Prometheus scraping
./scripts/setup-grafana-datasource.sh        # Grafana → Thanos connection
./scripts/seed-demo-certificates.sh          # 15 sample certificates
```

### Validation

```bash
# All pods should be Running and 1/1 Ready
oc get pods -n certchain
oc get pods -n certchain-techpulse
oc get pods -n certchain-dataforge
oc get pods -n certchain-neuralpath

# Quick smoke test
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')
curl -sk "https://verify-api-certchain.${DOMAIN}/api/v1/verify/TP-FSWD-001" | python3 -m json.tool
```

Expected: a JSON object with `"status": "ACTIVE"`.

### Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| Pods stuck in `Pending` | `oc describe pod <name> -n <ns>` | Cluster may lack resources. Check node capacity. |
| Pods in `CrashLoopBackOff` | `oc logs <pod> -n <ns>` | Usually a config issue. Check env vars and ConfigMaps. |
| Build fails | `oc get builds -n certchain` | Check build logs: `oc logs build/<name> -n certchain` |
| Keycloak not starting | `oc logs <kc-pod> -n <ns>` | Postgres may not be ready. Check PG pod first. |
| `curl` to route returns 503 | `oc get pods -n <ns>` | Pod may still be starting. Wait 30s and retry. |
| Identity brokering not working | Central KC admin console → Identity Providers | Run `./scripts/configure-identity-brokering.sh` again. |
| Channel setup job fails | `oc logs job/fabric-channel-setup -n certchain` | Orderers/peers may not be ready. Delete job and re-run. |
| Chaincode `CORE_CHAINCODE_ID_NAME` error | `oc logs deploy/certcontract -n certchain-techpulse` | Check ConfigMap `chaincode-id`: `oc get cm chaincode-id -n certchain-techpulse` |
| ArgoCD sync stuck | ArgoCD UI → Application → Sync Status | Terminate operation → delete stuck Job → force refresh |
| Gitea mirror job failed | `oc logs job/gitea-mirror -n showroom` | Check Gitea pod is running: `oc get pods -n showroom -l app.kubernetes.io/name=gitea` |

---

## Demo Walkthroughs

Interactive demo walkthroughs are available in the **Showroom** lab guide, which is deployed automatically with the platform. Showroom provides a split-pane interface with instructions on the left and interactive tabs on the right (terminal, OpenShift Console, Git repository, ArgoCD, and application UIs).

**Available walkthroughs in Showroom:**

| Walkthrough | What you do |
|---|---|
| **Issue Certificates** | Log in as a registrar, issue a certificate to the Fabric ledger |
| **Verify a Certificate** | Enter a cert ID as an employer — see public info only |
| **Student Transcript** | Log in as a student — identity brokering auto-routes to your org |
| **Security & Identity** | Explore Keycloak brokering, RBAC, MSP, and KC Organizations |
| **Monitoring** | Prometheus metrics, Grafana dashboards, PromQL queries |
| **Scalability** | Add a new org, scale peers and orderers |
| **Resilience** | Kill orderers, crash pods, prove BFT consensus works |
| **API Walkthrough** | curl commands from the terminal: issue, verify, revoke, transcript |

**Access Showroom:**

```bash
DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')
echo "https://showroom-showroom.${DOMAIN}"
```

**Teardown** (removes everything from the cluster):

```bash
./scripts/teardown-all.sh
```

---

## Scripts Reference

| Script | Purpose |
|---|---|
| `scripts/install.sh` | BYO cluster installer (`--repo-url` or `--gitea`) |
| `scripts/deploy-to-openshift.sh` | Imperative deploy for local development (7 steps) |
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

## Customizing Org Names

Organization names and the base namespace are defined in `env.sh`:

```bash
PROJECT_NAMESPACE="certchain"        # Base namespace (orgs become certchain-techpulse, etc.)
FABRIC_CHANNEL_NAME="certchannel"    # Hyperledger Fabric channel name
```

The three training organizations (TechPulse, DataForge, NeuralPath) are configured in `helm/bootstrap/values.yaml` under `components`. Each org defines its display name, Fabric MSP ID, and theme color. To rename or add organizations, update both `env.sh` (for imperative scripts) and the bootstrap values (for ArgoCD).

## Resource Requirements

Demo-sized: ~6 vCPU, ~7 GB RAM total across all components. Per-component resource limits are defined in each Helm chart's `values.yaml`.

## License

Apache License 2.0
