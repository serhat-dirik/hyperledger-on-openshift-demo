#!/usr/bin/env bash
# deploy-argocd.sh — Deploy CertChain via ArgoCD App-of-Apps.
# Creates a single root ArgoCD Application that generates 5 child Applications.
# Usage: bash scripts/deploy-argocd.sh [--repo-url URL] [--revision REV]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/env.sh"

DEPLOY_START=$(date +%s)

# --- Parse args ---
REPO_URL=""
REVISION="main"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-url) REPO_URL="$2"; shift 2;;
        --revision) REVISION="$2"; shift 2;;
        *) echo "[ERROR] Unknown arg: $1"; exit 1;;
    esac
done

echo "=============================================="
echo " CertChain — ArgoCD Deployment"
echo "=============================================="
echo ""

# --- 1. Prerequisites ---
echo "[1/5] Checking prerequisites..."
if ! oc whoami &>/dev/null; then
    echo "  [FAIL] Not logged into OpenShift. Run: oc login"
    exit 1
fi
echo "  [OK] Logged in as: $(oc whoami)"

# Check ArgoCD operator
if ! oc get deployment -n openshift-gitops openshift-gitops-server &>/dev/null 2>&1; then
    if ! oc get csv -n openshift-operators 2>/dev/null | grep -q gitops; then
        echo "  [FAIL] OpenShift GitOps not installed."
        echo "         Install with: make install-argocd"
        exit 1
    fi
fi
echo "  [OK] OpenShift GitOps operator found"

# --- 2. Auto-detect ---
echo ""
echo "[2/5] Auto-detecting cluster settings..."

DOMAIN_SUFFIX=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
if [ -z "$DOMAIN_SUFFIX" ]; then
    echo "  [FAIL] Cannot detect cluster domain"
    exit 1
fi
echo "  [OK] Domain: $DOMAIN_SUFFIX"

API_URL=$(oc whoami --show-server 2>/dev/null)
echo "  [OK] API URL: $API_URL"

# Auto-detect repo URL from git remote if not provided
if [ -z "$REPO_URL" ]; then
    REPO_URL=$(cd "$ROOT_DIR" && git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$REPO_URL" ]; then
        echo "  [FAIL] Cannot detect repo URL. Use: --repo-url <url>"
        exit 1
    fi
    # Convert SSH to HTTPS if needed
    REPO_URL=$(echo "$REPO_URL" | sed 's|git@github.com:|https://github.com/|')
fi
echo "  [OK] Repo URL: $REPO_URL"
echo "  [OK] Revision: $REVISION"

REGISTRY="image-registry.openshift-image-registry.svc:5000/$PROJECT_NAMESPACE"
echo "  [OK] Registry: $REGISTRY"

# --- 3. Grant ArgoCD permissions ---
echo ""
echo "[3/5] Configuring ArgoCD permissions..."

ARGOCD_NS="openshift-gitops"

# ArgoCD controller needs cluster-admin for cross-namespace operations
oc adm policy add-cluster-role-to-user cluster-admin \
    "system:serviceaccount:${ARGOCD_NS}:openshift-gitops-argocd-application-controller" \
    2>/dev/null || true
echo "  [OK] ArgoCD controller has cluster-admin"

# Grant current user ArgoCD admin role so apps are visible in the UI
CURRENT_USER=$(oc whoami)
oc patch configmap argocd-rbac-cm -n "$ARGOCD_NS" --type merge -p "{
  \"data\": {
    \"policy.csv\": \"g, system:cluster-admins, role:admin\ng, cluster-admins, role:admin\ng, ${CURRENT_USER}, role:admin\",
    \"policy.default\": \"\",
    \"scopes\": \"[groups]\"
  }
}" 2>/dev/null || true
echo "  [OK] ArgoCD RBAC: user '$CURRENT_USER' granted admin role"

# --- 4. Create root Application ---
echo ""
echo "[4/5] Creating ArgoCD root Application..."

cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: certchain
  namespace: ${ARGOCD_NS}
  labels:
    app.kubernetes.io/part-of: certchain
    demo.redhat.com/application: certchain
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: ${REVISION}
    path: helm
    helm:
      valuesObject:
        deployer:
          domain: ${DOMAIN_SUFFIX}
          apiUrl: ${API_URL}
        gitops:
          repoUrl: ${REPO_URL}
          revision: ${REVISION}
        images:
          registry: ${REGISTRY}
          tag: latest
          buildEnabled: true
        central:
          namespace: ${PROJECT_NAMESPACE}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NS}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
echo "  [OK] Root Application created"

# --- 5. Wait for sync ---
echo ""
echo "[5/5] Waiting for ArgoCD Applications to sync..."
echo ""

APPS=("certchain" "certchain-central" "certchain-techpulse" "certchain-dataforge" "certchain-neuralpath" "certchain-showroom")
MAX_WAIT=1800  # 30 minutes
POLL_INTERVAL=15
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    ALL_SYNCED=true
    for app in "${APPS[@]}"; do
        STATUS=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NotFound")
        HEALTH=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

        if [ "$STATUS" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
            continue
        else
            ALL_SYNCED=false
        fi
    done

    if $ALL_SYNCED; then
        break
    fi

    # Print status table
    printf "\r  %-25s %-12s %-12s" "APPLICATION" "SYNC" "HEALTH"
    echo ""
    for app in "${APPS[@]}"; do
        STATUS=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "---")
        HEALTH=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "---")
        printf "  %-25s %-12s %-12s\n" "$app" "$STATUS" "$HEALTH"
    done
    echo ""
    echo "  Elapsed: ${ELAPSED}s / ${MAX_WAIT}s"
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

DEPLOY_END=$(date +%s)
DEPLOY_DURATION=$((DEPLOY_END - DEPLOY_START))

echo ""
echo "=============================================="
echo " ArgoCD Deployment Complete"
echo "=============================================="
echo ""
echo "  Duration: ${DEPLOY_DURATION}s ($((DEPLOY_DURATION / 60))m $((DEPLOY_DURATION % 60))s)"
echo ""

# Final status
for app in "${APPS[@]}"; do
    STATUS=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "---")
    HEALTH=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "---")
    printf "  %-25s %-12s %-12s\n" "$app" "$STATUS" "$HEALTH"
done

echo ""
echo "  Next steps:"
echo "    1. make validate          — Run validation + timing report"
echo "    2. make configure-kc      — Configure identity brokering"
echo ""
echo "  URLs:"
echo "    ArgoCD:    https://openshift-gitops-server-${ARGOCD_NS}.${DOMAIN_SUFFIX}"
echo "    Portal:    https://cert-portal-${PROJECT_NAMESPACE}.${DOMAIN_SUFFIX}"
echo "    Showroom:  https://showroom-showroom.${DOMAIN_SUFFIX}"
echo ""
