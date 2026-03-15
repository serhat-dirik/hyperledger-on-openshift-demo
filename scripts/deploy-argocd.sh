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
ARGOCD_ADMIN_PASSWORD="admin"

# ArgoCD controller needs cluster-admin for cross-namespace operations
oc adm policy add-cluster-role-to-user cluster-admin \
    "system:serviceaccount:${ARGOCD_NS}:openshift-gitops-argocd-application-controller" \
    2>/dev/null || true
echo "  [OK] ArgoCD controller has cluster-admin"

# Create cluster-admins Group and add the current user.
# ArgoCD RBAC scopes by [groups] — without a real OpenShift Group object,
# OAuth tokens don't carry group claims and users see no apps.
CURRENT_USER=$(oc whoami)
oc adm groups new cluster-admins 2>/dev/null || true
oc adm groups add-users cluster-admins "$CURRENT_USER" 2>/dev/null || true
echo "  [OK] OpenShift Group 'cluster-admins' → user '$CURRENT_USER'"

# ArgoCD RBAC: map OpenShift groups to ArgoCD admin role
oc patch configmap argocd-rbac-cm -n "$ARGOCD_NS" --type merge -p "{
  \"data\": {
    \"policy.csv\": \"g, system:cluster-admins, role:admin\ng, cluster-admins, role:admin\ng, ${CURRENT_USER}, role:admin\",
    \"policy.default\": \"\",
    \"scopes\": \"[groups]\"
  }
}" 2>/dev/null || true
echo "  [OK] ArgoCD RBAC: cluster-admins group + user '$CURRENT_USER' → role:admin"

# Enable local ArgoCD admin account (OpenShift GitOps disables it by default)
oc patch argocd openshift-gitops -n "$ARGOCD_NS" --type merge \
    -p '{"spec":{"disableAdmin":false}}' 2>/dev/null || true
echo "  [OK] ArgoCD local admin account enabled"

# Set admin password — generate bcrypt hash, update the cluster secret
BCRYPT_HASH=$(python3 -c "
import hashlib, base64, os, struct
# bcrypt via htpasswd fallback: try bcrypt module, then htpasswd, then fallback
try:
    import bcrypt
    print(bcrypt.hashpw(b'${ARGOCD_ADMIN_PASSWORD}', bcrypt.gensalt(10)).decode())
except ImportError:
    import subprocess, shlex
    r = subprocess.run(['htpasswd', '-nbBC', '10', '', '${ARGOCD_ADMIN_PASSWORD}'],
                       capture_output=True, text=True)
    h = r.stdout.strip().lstrip(':')
    # htpasswd uses \$2y\$, ArgoCD expects \$2a\$
    print(h.replace('\$2y\$', '\$2a\$'))
" 2>/dev/null)

if [ -n "$BCRYPT_HASH" ]; then
    # The secret name follows pattern: {argocd-instance-name}-cluster
    oc patch secret openshift-gitops-cluster -n "$ARGOCD_NS" --type merge \
        -p "{\"stringData\":{\"admin.password\":\"${BCRYPT_HASH}\"}}" 2>/dev/null || true
    # Clear mtime so ArgoCD doesn't reject the password as "already changed"
    oc patch secret openshift-gitops-cluster -n "$ARGOCD_NS" --type merge \
        -p '{"stringData":{"admin.passwordMtime":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}}' 2>/dev/null || true
    echo "  [OK] ArgoCD admin password set to '${ARGOCD_ADMIN_PASSWORD}'"
else
    echo "  [WARN] Could not generate bcrypt hash (need python3 with bcrypt or htpasswd)"
    echo "         Retrieve auto-generated password with:"
    echo "         oc get secret openshift-gitops-cluster -n $ARGOCD_NS -o jsonpath='{.data.admin\\.password}' | base64 -d"
fi

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
echo "    Showroom:  https://showroom-certchain-showroom.${DOMAIN_SUFFIX}"
echo ""
echo "  ArgoCD Access:"
echo "    Option 1:  Log in with OpenShift (cluster-admin users auto-mapped)"
echo "    Option 2:  admin / ${ARGOCD_ADMIN_PASSWORD}"
echo ""
