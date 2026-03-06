#!/usr/bin/env bash
# teardown-all.sh — Removes the CertChain demo from the cluster.
# Uninstalls Helm releases, then deletes namespaces.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/env.sh"

CENTRAL_NS="$PROJECT_NAMESPACE"

echo "=== Tearing down CertChain Demo ==="

# Uninstall Helm releases
for org in techpulse dataforge neuralpath; do
    ns="${CENTRAL_NS}-${org}"
    echo "  Uninstalling certchain-${org} from $ns..."
    helm uninstall "certchain-${org}" -n "$ns" 2>/dev/null || true
done
echo "  Uninstalling certchain-central from $CENTRAL_NS..."
helm uninstall certchain-central -n "$CENTRAL_NS" 2>/dev/null || true

# Remove ArgoCD application (if any)
oc delete application certchain -n openshift-gitops 2>/dev/null || true
oc delete appproject certchain -n openshift-gitops 2>/dev/null || true

# Delete all namespaces (removes all remaining resources)
for ns in "$CENTRAL_NS" "${CENTRAL_NS}-techpulse" "${CENTRAL_NS}-dataforge" "${CENTRAL_NS}-neuralpath"; do
    echo "  Deleting namespace $ns..."
    oc delete project "$ns" --wait=false 2>/dev/null || true
done

# Wait for namespaces to be fully deleted
echo "  Waiting for namespace cleanup..."
for ns in "$CENTRAL_NS" "${CENTRAL_NS}-techpulse" "${CENTRAL_NS}-dataforge" "${CENTRAL_NS}-neuralpath"; do
    while oc get project "$ns" &>/dev/null 2>&1; do
        sleep 5
    done
    echo "  [OK] $ns deleted"
done

echo "Teardown complete."
