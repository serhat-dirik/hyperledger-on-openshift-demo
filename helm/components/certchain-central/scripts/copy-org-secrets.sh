#!/usr/bin/env bash
# copy-org-secrets.sh — Copies org secrets to central namespace with org-prefixed names.
# Waits for org enrollment to complete (cross-app dependency via retry loop).
set -euo pipefail
echo "TIMING_START $(date +%s)"

CENTRAL_NS="${CENTRAL_NS:-certchain}"
MAX_RETRIES="${MAX_RETRIES:-60}"
RETRY_INTERVAL="${RETRY_INTERVAL:-10}"

echo "=============================================="
echo " Copy Org Secrets to Central Namespace"
echo "=============================================="
echo ""

# Install kubectl if not present
if ! command -v kubectl &>/dev/null; then
    echo "Downloading kubectl..."
    mkdir -p /tmp/bin
    curl -sL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /tmp/bin/kubectl
    chmod +x /tmp/bin/kubectl
    export PATH="/tmp/bin:$PATH"
fi

# ── Idempotency check ──────────────────────────────────────────
# If org-prefixed secrets already exist in central, skip copying.
if kubectl get secret techpulse-admin-msp -n "$CENTRAL_NS" &>/dev/null \
   && kubectl get secret dataforge-admin-msp -n "$CENTRAL_NS" &>/dev/null \
   && kubectl get secret neuralpath-admin-msp -n "$CENTRAL_NS" &>/dev/null; then
    echo "[SKIP] Org secrets already exist in central namespace. Delete them to force re-run."
    echo "TIMING_END $(date +%s)"
    exit 0
fi
# ───────────────────────────────────────────────────────────────

# Wait for all org secrets to exist
echo "[1/2] Waiting for org enrollment to complete..."
for org in techpulse dataforge neuralpath; do
    org_ns="${CENTRAL_NS}-${org}"
    for secret in admin-msp peer0-tls orderer-msp orderer-tls; do
        echo "  Waiting for $secret in $org_ns..."
        for attempt in $(seq 1 "$MAX_RETRIES"); do
            if kubectl get secret "$secret" -n "$org_ns" &>/dev/null; then
                echo "  [OK] $secret exists in $org_ns"
                break
            fi
            if [ "$attempt" -eq "$MAX_RETRIES" ]; then
                echo "  [ERROR] Timeout waiting for $secret in $org_ns"
                exit 1
            fi
            sleep "$RETRY_INTERVAL"
        done
    done
done

# Copy secrets with org-prefixed names
echo "[2/2] Copying secrets..."
for org in techpulse dataforge neuralpath; do
    org_ns="${CENTRAL_NS}-${org}"

    # admin-msp → {org}-admin-msp, peer0-tls → peer0-{org}-tls
    for src_dest in "admin-msp:${org}-admin-msp" "peer0-tls:peer0-${org}-tls"; do
        IFS=: read -r src dest <<< "$src_dest"
        echo "  Copying $src ($org_ns) → $dest ($CENTRAL_NS)"
        kubectl get secret "$src" -n "$org_ns" -o yaml \
            | sed "s/namespace: $org_ns/namespace: $CENTRAL_NS/" \
            | sed "s/name: $src/name: $dest/" \
            | grep -v 'uid:\|resourceVersion:\|creationTimestamp:' \
            | kubectl apply -n "$CENTRAL_NS" -f - 2>/dev/null
    done

    # orderer TLS — orderer-tls → ordererN-{org}-tls
    case $org in
        techpulse)  oname="orderer1" ;;
        dataforge)  oname="orderer2" ;;
        neuralpath) oname="orderer3" ;;
    esac
    for suffix in msp tls; do
        src="orderer-${suffix}"
        dest="${oname}-${org}-${suffix}"
        echo "  Copying $src ($org_ns) → $dest ($CENTRAL_NS)"
        kubectl get secret "$src" -n "$org_ns" -o yaml \
            | sed "s/namespace: $org_ns/namespace: $CENTRAL_NS/" \
            | sed "s/name: $src/name: $dest/" \
            | grep -v 'uid:\|resourceVersion:\|creationTimestamp:' \
            | kubectl apply -n "$CENTRAL_NS" -f - 2>/dev/null
    done
done

echo ""
echo "  [OK] All org secrets copied to $CENTRAL_NS"
echo "TIMING_END $(date +%s)"
