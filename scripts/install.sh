#!/usr/bin/env bash
# =============================================================================
# CertChain — BYO Cluster Installer
# =============================================================================
# Installs CertChain on any OpenShift 4.16+ cluster via ArgoCD.
#
# Usage:
#   ./scripts/install.sh --repo-url https://github.com/you/your-fork.git
#   ./scripts/install.sh --gitea
#
# Options:
#   --repo-url <url>   Use your own writable Git repo (fork) as ArgoCD source
#   --gitea            Install local Gitea, mirror public repo, use as source
#   --help             Show this help message
# =============================================================================

set -euo pipefail

# --- Defaults ---------------------------------------------------------------
REPO_URL=""
USE_GITEA=false
SOURCE_REPO="https://github.com/serhat-dirik/hyperledger-on-openshift-demo.git"
BOOTSTRAP_PATH="helm/bootstrap"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Parse arguments --------------------------------------------------------
usage() {
  echo "Usage: $0 [--repo-url <url> | --gitea]"
  echo ""
  echo "Options:"
  echo "  --repo-url <url>   Your writable Git repo (fork of CertChain)"
  echo "  --gitea            Install Gitea and mirror the public repo"
  echo "  --help             Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 --repo-url https://github.com/johndoe/hyperledger-on-openshift-demo.git"
  echo "  $0 --gitea"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --gitea)
      USE_GITEA=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      usage
      ;;
  esac
done

# Validate: must provide exactly one of --repo-url or --gitea
if [[ -z "$REPO_URL" && "$USE_GITEA" == "false" ]]; then
  echo -e "${RED}ERROR: Provide either --repo-url <url> or --gitea${NC}"
  echo ""
  usage
fi

if [[ -n "$REPO_URL" && "$USE_GITEA" == "true" ]]; then
  echo -e "${RED}ERROR: Cannot use both --repo-url and --gitea${NC}"
  echo ""
  usage
fi

# --- Step 1: Verify prerequisites -------------------------------------------
echo -e "${BLUE}=== Step 1: Verifying prerequisites ===${NC}"

# Check oc is available
if ! command -v oc &> /dev/null; then
  echo -e "${RED}ERROR: 'oc' CLI not found. Install it from:${NC}"
  echo "  https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/"
  exit 1
fi

# Check logged in
if ! oc whoami &> /dev/null; then
  echo -e "${RED}ERROR: Not logged into OpenShift. Run 'oc login' first.${NC}"
  exit 1
fi
echo -e "  Logged in as: ${GREEN}$(oc whoami)${NC}"

# Check cluster-admin
if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
  echo -e "${RED}ERROR: cluster-admin access required.${NC}"
  exit 1
fi
echo -e "  Cluster-admin: ${GREEN}yes${NC}"

# Check OpenShift version
OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
echo -e "  OpenShift version: ${GREEN}${OCP_VERSION}${NC}"

# --- Step 2: Auto-detect cluster info ---------------------------------------
echo -e "\n${BLUE}=== Step 2: Detecting cluster configuration ===${NC}"

DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}')
API_URL=$(oc whoami --show-server)

echo -e "  Domain:  ${GREEN}${DOMAIN}${NC}"
echo -e "  API URL: ${GREEN}${API_URL}${NC}"

# --- Step 3: Ensure ArgoCD is installed -------------------------------------
echo -e "\n${BLUE}=== Step 3: Checking ArgoCD / OpenShift GitOps ===${NC}"

if oc get csv -n openshift-gitops -l operators.coreos.com/openshift-gitops-operator.openshift-gitops 2>/dev/null | grep -q Succeeded; then
  echo -e "  OpenShift GitOps: ${GREEN}installed${NC}"
elif oc get namespace openshift-gitops &> /dev/null; then
  echo -e "  OpenShift GitOps namespace exists, checking pods..."
  oc wait --for=condition=available deployment/openshift-gitops-server -n openshift-gitops --timeout=120s
  echo -e "  OpenShift GitOps: ${GREEN}ready${NC}"
else
  echo -e "  ${YELLOW}OpenShift GitOps not found. Installing...${NC}"
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  echo "  Waiting for operator to install (up to 3 minutes)..."
  sleep 30
  for i in $(seq 1 30); do
    if oc get deployment openshift-gitops-server -n openshift-gitops &> /dev/null; then
      oc wait --for=condition=available deployment/openshift-gitops-server -n openshift-gitops --timeout=120s
      break
    fi
    echo "    Waiting... ($i/30)"
    sleep 10
  done
  echo -e "  OpenShift GitOps: ${GREEN}installed${NC}"
fi

# --- Step 4: Determine target repo ------------------------------------------
echo -e "\n${BLUE}=== Step 4: Configuring source repository ===${NC}"

GITEA_ENABLED="false"
TARGET_REPO=""

if [[ "$USE_GITEA" == "true" ]]; then
  GITEA_ENABLED="true"
  TARGET_REPO="(Gitea — will be provisioned by bootstrap)"
  echo -e "  Mode: ${GREEN}Gitea (local mirror)${NC}"
  echo -e "  Source: ${SOURCE_REPO}"
  echo -e "  Gitea will be available at: https://gitea-certchain-showroom.${DOMAIN}"
else
  TARGET_REPO="${REPO_URL}"
  echo -e "  Mode: ${GREEN}External repo (your fork)${NC}"
  echo -e "  Repo: ${TARGET_REPO}"
fi

# --- Step 5: Create ArgoCD Application --------------------------------------
echo -e "\n${BLUE}=== Step 5: Creating ArgoCD Application ===${NC}"

# Determine which repo URL ArgoCD should pull the bootstrap chart from
if [[ "$USE_GITEA" == "true" ]]; then
  # Bootstrap itself always comes from the public GitHub repo
  BOOTSTRAP_REPO="${SOURCE_REPO}"
else
  # User's fork contains the bootstrap chart
  BOOTSTRAP_REPO="${REPO_URL}"
fi

cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: certchain-bootstrap
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/part-of: certchain
    demo.redhat.com/application: "certchain"
spec:
  project: default
  source:
    repoURL: ${BOOTSTRAP_REPO}
    targetRevision: main
    path: ${BOOTSTRAP_PATH}
    helm:
      values: |
        deployer:
          domain: "${DOMAIN}"
          apiUrl: "${API_URL}"
        gitea:
          enabled: ${GITEA_ENABLED}
        sourceRepo:
          url: "${SOURCE_REPO}"
          revision: "main"
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
      - CreateNamespace=true
EOF

echo -e "  ArgoCD Application created: ${GREEN}certchain-bootstrap${NC}"

# --- Step 6: Wait for sync --------------------------------------------------
echo -e "\n${BLUE}=== Step 6: Waiting for bootstrap sync ===${NC}"

echo "  Waiting for bootstrap to sync (this may take a few minutes)..."
for i in $(seq 1 60); do
  STATUS=$(oc get application certchain-bootstrap -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  HEALTH=$(oc get application certchain-bootstrap -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
    echo -e "  Bootstrap: ${GREEN}Synced and Healthy${NC}"
    break
  fi
  echo "    Status: ${STATUS} / Health: ${HEALTH} ($i/60)"
  sleep 15
done

# Check for child applications
echo -e "\n  Checking child applications..."
sleep 10
oc get applications -n openshift-gitops -l app.kubernetes.io/part-of=certchain --no-headers 2>/dev/null || true

# --- Step 7: Print summary --------------------------------------------------
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}  CertChain installation initiated!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "  ${YELLOW}ArgoCD is now deploying all components.${NC}"
echo -e "  ${YELLOW}Full deployment takes 10-15 minutes.${NC}"
echo ""
echo -e "  Monitor progress:"
echo -e "    ArgoCD:    ${GREEN}https://openshift-gitops-server-openshift-gitops.${DOMAIN}${NC}"
echo -e "               (admin / admin  or  Log in via OpenShift)"
echo ""
echo -e "  After deployment completes:"
echo -e "    Showroom:  ${GREEN}https://showroom-certchain-showroom.${DOMAIN}${NC}"
echo -e "    Portal:    ${GREEN}https://cert-portal-certchain.${DOMAIN}${NC}"
if [[ "$USE_GITEA" == "true" ]]; then
echo -e "    Gitea:     ${GREEN}https://gitea-certchain-showroom.${DOMAIN}${NC}"
echo -e "               (gitea / openshift)"
fi
echo ""
echo -e "  ${YELLOW}Post-deploy steps (run after all pods are ready):${NC}"
echo -e "    1. Configure identity brokering: ./scripts/configure-identity-brokering.sh"
echo -e "    2. Enable monitoring:            ./scripts/setup-enable-user-workload-monitoring.sh"
echo -e "    3. Seed demo data:               ./scripts/seed-demo-certificates.sh"
echo ""
