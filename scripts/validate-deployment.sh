#!/usr/bin/env bash
# validate-deployment.sh — Validate CertChain ArgoCD deployment and generate timing report.
# Usage: bash scripts/validate-deployment.sh
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

DOMAIN_SUFFIX=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
CENTRAL_NS="$PROJECT_NAMESPACE"
ARGOCD_NS="openshift-gitops"
ALL_NS=("$CENTRAL_NS" "${CENTRAL_NS}-techpulse" "${CENTRAL_NS}-dataforge" "${CENTRAL_NS}-neuralpath" "${CENTRAL_NS}-showroom")

echo "=============================================="
echo " CertChain — Deployment Validation"
echo "=============================================="
echo ""

# --- 1. ArgoCD Application status ---
echo "[1/5] ArgoCD Application status..."
APPS=("certchain" "certchain-central" "certchain-techpulse" "certchain-dataforge" "certchain-neuralpath" "certchain-showroom")
for app in "${APPS[@]}"; do
    STATUS=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NotFound")
    HEALTH=$(oc get application "$app" -n "$ARGOCD_NS" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
        pass "$app: Synced/Healthy"
    elif [ "$STATUS" = "Synced" ]; then
        warn "$app: Synced but $HEALTH"
    else
        fail "$app: $STATUS / $HEALTH"
    fi
done

# --- 2. Pod readiness ---
echo ""
echo "[2/5] Pod readiness across namespaces..."
for ns in "${ALL_NS[@]}"; do
    TOTAL=$(oc get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    RUNNING=$(oc get pods -n "$ns" --no-headers 2>/dev/null | grep -cE "Running|Completed" || echo "0")
    if [ "$TOTAL" -eq 0 ]; then
        warn "$ns: no pods found"
    elif [ "$RUNNING" -eq "$TOTAL" ]; then
        pass "$ns: $RUNNING/$TOTAL pods Running/Completed"
    else
        fail "$ns: $RUNNING/$TOTAL pods Running/Completed"
        oc get pods -n "$ns" --no-headers 2>/dev/null | grep -vE "Running|Completed" | while read -r line; do
            echo "    $line"
        done
    fi
done

# --- 3. Job completion status ---
echo ""
echo "[3/5] Job completion status..."
JOBS=(
    "$CENTRAL_NS:central-enrollment"
    "$CENTRAL_NS:genesis-generation"
    "$CENTRAL_NS:copy-org-secrets"
    "$CENTRAL_NS:channel-setup"
    "$CENTRAL_NS:chaincode-lifecycle"
    "${CENTRAL_NS}-techpulse:org-enrollment"
    "${CENTRAL_NS}-dataforge:org-enrollment"
    "${CENTRAL_NS}-neuralpath:org-enrollment"
)
for job_spec in "${JOBS[@]}"; do
    ns="${job_spec%%:*}"
    job="${job_spec##*:}"
    STATUS=$(oc get job "$job" -n "$ns" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [ "$STATUS" = "1" ]; then
        pass "$ns/$job: Completed"
    else
        FAILED=$(oc get job "$job" -n "$ns" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
        if [ "${FAILED:-0}" -gt 0 ]; then
            fail "$ns/$job: Failed ($FAILED attempts)"
        else
            warn "$ns/$job: Not completed yet (succeeded=$STATUS)"
        fi
    fi
done

# --- 4. Timing report ---
echo ""
echo "[4/5] Timing report (from Job logs)..."
echo ""
printf "  %-35s %-12s %-12s %-10s\n" "JOB" "START" "END" "DURATION"
printf "  %-35s %-12s %-12s %-10s\n" "---" "-----" "---" "--------"

for job_spec in "${JOBS[@]}"; do
    ns="${job_spec%%:*}"
    job="${job_spec##*:}"
    POD=$(oc get pods -n "$ns" -l "job-name=$job" --no-headers 2>/dev/null | head -1 | awk '{print $1}')
    if [ -z "$POD" ]; then
        printf "  %-35s %-12s %-12s %-10s\n" "$ns/$job" "---" "---" "no pod"
        continue
    fi

    # Extract TIMING markers from logs
    START_TS=$(oc logs "$POD" -n "$ns" 2>/dev/null | grep "TIMING_START" | head -1 | awk '{print $2}' || echo "")
    END_TS=$(oc logs "$POD" -n "$ns" 2>/dev/null | grep "TIMING_END" | tail -1 | awk '{print $2}' || echo "")

    if [ -n "$START_TS" ] && [ -n "$END_TS" ]; then
        DURATION=$((END_TS - START_TS))
        printf "  %-35s %-12s %-12s %-10s\n" "$ns/$job" "$START_TS" "$END_TS" "${DURATION}s"
    else
        # Fall back to pod creation/completion times
        CREATED=$(oc get pod "$POD" -n "$ns" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")
        FINISHED=$(oc get pod "$POD" -n "$ns" -o jsonpath='{.status.containerStatuses[0].state.terminated.finishedAt}' 2>/dev/null || echo "")
        if [ -n "$CREATED" ] && [ -n "$FINISHED" ]; then
            START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED" +%s 2>/dev/null || date -d "$CREATED" +%s 2>/dev/null || echo "0")
            END_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$FINISHED" +%s 2>/dev/null || date -d "$FINISHED" +%s 2>/dev/null || echo "0")
            if [ "$START_EPOCH" -gt 0 ] && [ "$END_EPOCH" -gt 0 ]; then
                DURATION=$((END_EPOCH - START_EPOCH))
                printf "  %-35s %-12s %-12s %-10s\n" "$ns/$job" "pod-create" "pod-finish" "${DURATION}s"
            else
                printf "  %-35s %-12s %-12s %-10s\n" "$ns/$job" "---" "---" "parse err"
            fi
        else
            printf "  %-35s %-12s %-12s %-10s\n" "$ns/$job" "---" "---" "no times"
        fi
    fi
done

# --- 5. Smoke tests ---
echo ""
echo "[5/5] Endpoint smoke tests..."

# Cert Portal
PORTAL_URL="https://cert-portal-${CENTRAL_NS}.${DOMAIN_SUFFIX}"
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "$PORTAL_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "Cert Portal ($HTTP_CODE): $PORTAL_URL"
else
    warn "Cert Portal ($HTTP_CODE): $PORTAL_URL"
fi

# Verify API health
VERIFY_URL="https://verify-api-${CENTRAL_NS}.${DOMAIN_SUFFIX}/q/health"
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "$VERIFY_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "Verify API health ($HTTP_CODE)"
else
    warn "Verify API health ($HTTP_CODE): $VERIFY_URL"
fi

# Showroom
SHOWROOM_URL="https://showroom-certchain-showroom.${DOMAIN_SUFFIX}"
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "$SHOWROOM_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "Showroom ($HTTP_CODE): $SHOWROOM_URL"
else
    warn "Showroom ($HTTP_CODE): $SHOWROOM_URL"
fi

# --- Summary ---
echo ""
echo "=============================================="
echo " Validation Summary"
echo "=============================================="
echo "  Passed:   $PASS"
echo "  Warnings: $WARN"
echo "  Failed:   $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "  STATUS: ISSUES FOUND"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "  STATUS: MOSTLY OK (review warnings)"
    exit 0
else
    echo "  STATUS: ALL CHECKS PASSED"
    exit 0
fi
