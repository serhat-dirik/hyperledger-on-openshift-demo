#!/usr/bin/env bash
# teardown-all.sh — Removes the CertChain demo from the cluster.
# Deletes ArgoCD Applications, Helm releases, and all namespaces.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/env.sh"

CENTRAL_NS="$PROJECT_NAMESPACE"
ALL_NS=("$CENTRAL_NS" "${CENTRAL_NS}-techpulse" "${CENTRAL_NS}-dataforge" "${CENTRAL_NS}-neuralpath" "${CENTRAL_NS}-showroom")

echo "=== Tearing down CertChain Demo ==="

# Remove ArgoCD applications (bootstrap + children)
echo "  Removing ArgoCD Applications..."
for app in certchain-bootstrap certchain-central certchain-techpulse certchain-dataforge certchain-neuralpath certchain-showroom; do
    oc delete application "$app" -n openshift-gitops --wait=false 2>/dev/null || true
done
oc delete appproject certchain -n openshift-gitops 2>/dev/null || true

# Uninstall Helm releases (if any remain after ArgoCD cleanup)
for org in techpulse dataforge neuralpath; do
    ns="${CENTRAL_NS}-${org}"
    echo "  Uninstalling certchain-${org} from $ns..."
    helm uninstall "certchain-${org}" -n "$ns" 2>/dev/null || true
done
echo "  Uninstalling certchain-central from $CENTRAL_NS..."
helm uninstall certchain-central -n "$CENTRAL_NS" 2>/dev/null || true

# Delete all namespaces (removes all remaining resources)
for ns in "${ALL_NS[@]}"; do
    echo "  Deleting namespace $ns..."
    oc delete project "$ns" --wait=false 2>/dev/null || true
done

# Wait for namespaces to be fully deleted
echo "  Waiting for namespace cleanup..."
for ns in "${ALL_NS[@]}"; do
    while oc get project "$ns" &>/dev/null 2>&1; do
        sleep 5
    done
    echo "  [OK] $ns deleted"
done

echo ""
echo "Teardown complete. All CertChain resources removed."
echo ""
echo "Note: OpenShift GitOps (ArgoCD) operator was not removed."
echo "To remove it: oc delete subscription openshift-gitops-operator -n openshift-operators"
