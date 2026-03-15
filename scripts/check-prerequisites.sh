#!/usr/bin/env bash
# check-prerequisites.sh — Validates OpenShift cluster readiness for CertChain demo.
# Checks: connectivity, version, operators, resources, and required tooling.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/env.sh"

PASS=0
WARN=0
FAIL=0

pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=============================================="
echo " CertChain Demo — Platform Readiness Check"
echo "=============================================="
echo ""

# --- 1. Local tooling ---
echo "[1/7] Checking local tools..."
for cmd in oc helm curl python3 make; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd: available"
    else
        fail "$cmd: not found (required)"
    fi
done
for cmd in podman; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd: available"
    else
        warn "$cmd: not found (needed for local image builds)"
    fi
done

# --- 2. OpenShift connectivity ---
echo ""
echo "[2/7] Checking OpenShift connectivity..."
if oc whoami &>/dev/null; then
    USER=$(oc whoami)
    SERVER=$(oc whoami --show-server)
    pass "Logged in as: $USER"
    pass "API server: $SERVER"
else
    fail "Not logged into OpenShift. Run: oc login <api-url>"
    echo ""
    echo "=== Cannot continue without cluster access ==="
    echo "  Results: $PASS passed, $WARN warnings, $FAIL failed"
    exit 1
fi

# --- 3. OpenShift version ---
echo ""
echo "[3/7] Checking OpenShift version..."
OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
if [ "$OCP_VERSION" != "unknown" ]; then
    MAJOR_MINOR=$(echo "$OCP_VERSION" | cut -d. -f1-2)
    pass "OpenShift version: $OCP_VERSION"
    if awk "BEGIN {exit !($MAJOR_MINOR >= 4.16)}"; then
        pass "Version >= 4.16"
    else
        warn "Version $OCP_VERSION may be below minimum 4.16"
    fi
else
    warn "Could not determine OpenShift version"
fi

# --- 4. Cluster domain ---
echo ""
echo "[4/7] Checking cluster ingress domain..."
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
if [ -n "$CLUSTER_DOMAIN" ]; then
    pass "Ingress domain: $CLUSTER_DOMAIN"
else
    fail "Cannot detect ingress domain"
fi

# --- 5. Namespace and permissions ---
echo ""
echo "[5/7] Checking namespace and permissions..."
if oc get namespace "$PROJECT_NAMESPACE" &>/dev/null; then
    pass "Namespace '$PROJECT_NAMESPACE' exists"
else
    warn "Namespace '$PROJECT_NAMESPACE' does not exist yet (will be created by deploy)"
fi

# Check if user can create resources
if oc auth can-i create deployments -n "$PROJECT_NAMESPACE" &>/dev/null; then
    pass "Can create Deployments in $PROJECT_NAMESPACE"
else
    warn "May not have permission to create Deployments in $PROJECT_NAMESPACE"
fi

if oc auth can-i create routes -n "$PROJECT_NAMESPACE" &>/dev/null; then
    pass "Can create Routes in $PROJECT_NAMESPACE"
else
    warn "May not have permission to create Routes"
fi

# --- 6. Operators ---
echo ""
echo "[6/7] Checking operators..."

# ArgoCD / OpenShift GitOps
if oc get csv -n openshift-operators 2>/dev/null | grep -q gitops; then
    pass "OpenShift GitOps operator: installed"
elif oc get deployment -n openshift-gitops openshift-gitops-server &>/dev/null 2>&1; then
    pass "OpenShift GitOps: running"
else
    warn "OpenShift GitOps not detected. Install with: make install-argocd"
fi

# --- 7. Resource capacity ---
echo ""
echo "[7/7] Checking cluster resource capacity..."
NODE_COUNT=$(oc get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NODE_COUNT" -gt 0 ]; then
    pass "$NODE_COUNT node(s) available"
else
    fail "No nodes available"
fi

READY_NODES=$(oc get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
if [ "$READY_NODES" -gt 0 ]; then
    pass "$READY_NODES node(s) in Ready state"
else
    fail "No nodes in Ready state"
fi

# Estimate resource needs (rough)
echo ""
echo "  Resource estimate for CertChain demo:"
echo "    Fabric (4 orderers+3 peers+3 CouchDB+CA): ~2.1 CPU, ~2.5 Gi RAM"
echo "    Quarkus APIs (4 cert-admin + 1 verify):    ~1.0 CPU, ~1.3 Gi RAM"
echo "    Keycloak (4 instances + 4 PostgreSQL):     ~1.2 CPU, ~3.0 Gi RAM"
echo "    Frontends (3 course-mgr + 1 portal):       ~0.2 CPU, ~0.3 Gi RAM"
echo "    Total estimate:                             ~4.5 CPU, ~7.1 Gi RAM"

# --- Summary ---
echo ""
echo "=============================================="
echo " Platform Readiness Summary"
echo "=============================================="
echo "  Passed:   $PASS"
echo "  Warnings: $WARN"
echo "  Failed:   $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "  STATUS: NOT READY — Fix failures above before deploying."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "  STATUS: READY WITH WARNINGS — Review warnings above."
    echo ""
    echo "  Next steps:"
    echo "    ./scripts/install.sh --gitea           # Install with local Gitea"
    echo "    ./scripts/install.sh --repo-url <url>  # Install from your fork"
    exit 0
else
    echo "  STATUS: READY"
    echo ""
    echo "  Next steps:"
    echo "    ./scripts/install.sh --gitea           # Install with local Gitea"
    echo "    ./scripts/install.sh --repo-url <url>  # Install from your fork"
    exit 0
fi
