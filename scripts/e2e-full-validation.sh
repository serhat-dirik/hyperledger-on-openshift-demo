#!/usr/bin/env bash
# e2e-full-validation.sh — End-to-end validation of the CertChain demo.
#
# Runs a complete validation: teardown (optional) → install → deploy →
# configure → seed → API tests → monitoring tests → summary report.
#
# Usage:
#   ./scripts/e2e-full-validation.sh              # skip teardown, validate existing deployment
#   ./scripts/e2e-full-validation.sh --clean       # teardown first, then full install + validate
#
# Exit codes:
#   0  — all tests passed
#   1  — one or more tests failed (see summary)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/env.sh"

# --- Auto-detect domain suffix ---
if [ -z "${DOMAIN_SUFFIX:-}" ]; then
    if command -v oc &>/dev/null && oc whoami &>/dev/null 2>&1; then
        DETECTED_DOMAIN=$(oc get ingresses.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
        if [ -n "$DETECTED_DOMAIN" ]; then
            DOMAIN_SUFFIX="$DETECTED_DOMAIN"
        fi
    fi
fi

if [ -z "${DOMAIN_SUFFIX:-}" ]; then
    echo "ERROR: DOMAIN_SUFFIX not set and could not auto-detect via 'oc'."
    echo "Usage: DOMAIN_SUFFIX=apps.example.com $0"
    exit 1
fi

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- State ---
CLEAN=false
PASS=0
FAIL=0
SKIP=0
RESULTS=()

for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
    esac
done

# --- Helpers ---
banner() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

record_pass() {
    PASS=$((PASS + 1))
    RESULTS+=("${GREEN}✓${NC} $1")
    echo -e "  ${GREEN}✓ PASS${NC} — $1"
}

record_fail() {
    FAIL=$((FAIL + 1))
    RESULTS+=("${RED}✗${NC} $1")
    echo -e "  ${RED}✗ FAIL${NC} — $1"
}

record_skip() {
    SKIP=$((SKIP + 1))
    RESULTS+=("${YELLOW}⊘${NC} $1")
    echo -e "  ${YELLOW}⊘ SKIP${NC} — $1"
}

wait_for_pods() {
    local ns=$1 timeout=${2:-120} elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local not_ready
        not_ready=$(oc get pods -n "$ns" --no-headers 2>/dev/null \
            | { grep -v "\-build " || true; } \
            | { grep -v "Running\|Completed\|Succeeded" || true; } | wc -l | tr -d ' ')
        if [ "$not_ready" = "0" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

# --- Title ---
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║   CertChain — End-to-End Full Validation              ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

if [ "$CLEAN" = true ]; then
    echo "  Mode: CLEAN (teardown → full install → validate)"
else
    echo "  Mode: VALIDATE (test existing deployment)"
fi
echo ""

# ============================================================================
# Phase 0: Teardown (optional)
# ============================================================================
if [ "$CLEAN" = true ]; then
    banner "Phase 0: Teardown Existing Deployment"

    if [ -f "$SCRIPT_DIR/teardown-all.sh" ]; then
        echo "  Running teardown-all.sh..."
        bash "$SCRIPT_DIR/teardown-all.sh" 2>&1 | sed 's/^/    /'
        record_pass "Teardown completed"
    else
        record_skip "teardown-all.sh not found"
    fi

    # ============================================================================
    # Phase 1: Setup
    # ============================================================================
    banner "Phase 1: Setup & Bootstrap"

    echo "  Running setup-all.sh..."
    if bash "$SCRIPT_DIR/setup-all.sh" 2>&1 | sed 's/^/    /'; then
        record_pass "setup-all.sh completed"
    else
        record_fail "setup-all.sh failed"
    fi

    # ============================================================================
    # Phase 2: Deploy
    # ============================================================================
    banner "Phase 2: Deploy to OpenShift"

    echo "  Running deploy-to-openshift.sh..."
    if bash "$SCRIPT_DIR/deploy-to-openshift.sh" 2>&1 | sed 's/^/    /'; then
        record_pass "deploy-to-openshift.sh completed"
    else
        record_fail "deploy-to-openshift.sh failed"
    fi

    # ============================================================================
    # Phase 3: Configure Identity Brokering
    # ============================================================================
    banner "Phase 3: Configure Identity Brokering"

    if [ -f "$SCRIPT_DIR/configure-identity-brokering.sh" ]; then
        echo "  Running configure-identity-brokering.sh..."
        if bash "$SCRIPT_DIR/configure-identity-brokering.sh" 2>&1 | sed 's/^/    /'; then
            record_pass "Identity brokering configured"
        else
            record_fail "Identity brokering configuration failed"
        fi
    else
        record_skip "configure-identity-brokering.sh not found"
    fi

    # ============================================================================
    # Phase 4: Enable Monitoring
    # ============================================================================
    banner "Phase 4: Enable Monitoring"

    if [ -f "$SCRIPT_DIR/setup-enable-user-workload-monitoring.sh" ]; then
        echo "  Enabling user workload monitoring..."
        if bash "$SCRIPT_DIR/setup-enable-user-workload-monitoring.sh" 2>&1 | sed 's/^/    /'; then
            record_pass "User workload monitoring enabled"
        else
            record_fail "User workload monitoring setup failed"
        fi
    else
        record_skip "setup-enable-user-workload-monitoring.sh not found"
    fi

    if [ -f "$SCRIPT_DIR/setup-grafana-datasource.sh" ]; then
        echo "  Configuring Grafana datasource..."
        if bash "$SCRIPT_DIR/setup-grafana-datasource.sh" 2>&1 | sed 's/^/    /'; then
            record_pass "Grafana datasource configured"
        else
            record_fail "Grafana datasource setup failed"
        fi
    else
        record_skip "setup-grafana-datasource.sh not found"
    fi

    # ============================================================================
    # Phase 5: Seed Demo Data
    # ============================================================================
    banner "Phase 5: Seed Demo Data"

    if [ -f "$SCRIPT_DIR/seed-demo-certificates.sh" ]; then
        echo "  Seeding demo certificates..."
        if bash "$SCRIPT_DIR/seed-demo-certificates.sh" 2>&1 | sed 's/^/    /'; then
            record_pass "Demo data seeded"
        else
            record_fail "Seed script failed"
        fi
    else
        record_skip "seed-demo-certificates.sh not found"
    fi
fi

# ============================================================================
# Phase 6: Validate Pods
# ============================================================================
banner "Phase 6: Validate Pod Health"

for ns in certchain certchain-techpulse certchain-dataforge certchain-neuralpath; do
    echo "  Checking $ns..."
    # Exclude build pods (OpenShift BuildConfig artifacts) — they are expected to be Completed/Error
    pod_count=$(oc get pods -n "$ns" --no-headers 2>/dev/null | { grep -v "\-build " || true; } | wc -l | tr -d ' ')
    if [ "$pod_count" = "0" ]; then
        record_fail "No pods in $ns"
        continue
    fi

    not_ready=$(oc get pods -n "$ns" --no-headers 2>/dev/null \
        | { grep -v "\-build " || true; } \
        | { grep -v "Running\|Completed\|Succeeded" || true; } | wc -l | tr -d ' ')
    if [ "$not_ready" = "0" ]; then
        record_pass "All $pod_count service pods running in $ns"
    else
        record_fail "$not_ready pods not ready in $ns"
        oc get pods -n "$ns" --no-headers 2>/dev/null \
            | { grep -v "\-build " || true; } \
            | { grep -v "Running\|Completed\|Succeeded" || true; } | sed 's/^/    /'
    fi
done

# ============================================================================
# Phase 7: Validate Routes
# ============================================================================
banner "Phase 7: Validate Routes & Endpoints"

check_url() {
    local name=$1 url=$2 expected=${3:-200}
    local http_code
    http_code=$(curl -sS -k -o /dev/null -w "%{http_code}" --connect-timeout 10 "$url" 2>/dev/null || echo "000")
    if [ "$http_code" = "$expected" ]; then
        record_pass "$name (HTTP $http_code)"
    else
        record_fail "$name (HTTP $http_code, expected $expected)"
    fi
}

echo "  Testing application endpoints..."
check_url "CertChain Portal" "https://cert-portal-certchain.${DOMAIN_SUFFIX}" 200
check_url "Verify API health" "https://verify-api-certchain.${DOMAIN_SUFFIX}/q/health/ready" 200
check_url "TechPulse Course Manager" "https://course-manager-ui-certchain-techpulse.${DOMAIN_SUFFIX}" 200
check_url "TechPulse cert-admin-api health" "https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}/q/health/ready" 200
check_url "DataForge cert-admin-api health" "https://cert-admin-api-certchain-dataforge.${DOMAIN_SUFFIX}/q/health/ready" 200
check_url "NeuralPath cert-admin-api health" "https://cert-admin-api-certchain-neuralpath.${DOMAIN_SUFFIX}/q/health/ready" 200

echo ""
echo "  Testing Keycloak endpoints..."
# KC 26.x serves /health/* on management port 9000, not app port 8080.
# Routes target port 8080, so use /realms/master which returns 200 on the app port.
check_url "Central Keycloak" "https://keycloak-certchain.${DOMAIN_SUFFIX}/realms/master" 200
check_url "TechPulse Keycloak" "https://keycloak-certchain-techpulse.${DOMAIN_SUFFIX}/realms/techpulse" 200
check_url "DataForge Keycloak" "https://keycloak-certchain-dataforge.${DOMAIN_SUFFIX}/realms/dataforge" 200
check_url "NeuralPath Keycloak" "https://keycloak-certchain-neuralpath.${DOMAIN_SUFFIX}/realms/neuralpath" 200

# ============================================================================
# Phase 8: API Tests — Authentication
# ============================================================================
banner "Phase 8: API Tests — Authentication & Certificate Lifecycle"

echo "  Authenticating as TechPulse registrar..."
TOKEN=$(curl -sS -k "https://keycloak-certchain-techpulse.${DOMAIN_SUFFIX}/realms/techpulse/protocol/openid-connect/token" \
    -d "client_id=course-manager-ui" \
    -d "username=admin@techpulse.demo" \
    -d "password=admin" \
    -d "grant_type=password" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
    record_pass "Keycloak authentication (TechPulse)"
else
    record_fail "Keycloak authentication (TechPulse) — no token received"
    # Skip remaining API tests
    record_skip "Certificate issuance (no auth token)"
    record_skip "Certificate verification (no auth token)"
    record_skip "Certificate revocation (no auth token)"
    record_skip "Re-verification after revocation (no auth token)"
fi

if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
    # Dashboard stats
    echo "  Testing dashboard stats..."
    STATS_HTTP=$(curl -sS -k -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}/api/v1/dashboard/stats" 2>/dev/null || echo "000")
    if [ "$STATS_HTTP" = "200" ]; then
        record_pass "Dashboard stats API"
    else
        record_fail "Dashboard stats API (HTTP $STATS_HTTP)"
    fi

    # Issue a certificate
    E2E_CERT_ID="E2E-$(date +%Y%m%d%H%M%S)"
    echo "  Issuing test certificate: $E2E_CERT_ID..."
    ISSUE_HTTP=$(curl -sS -k -X POST \
        "https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}/api/v1/certificates" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"certID\": \"$E2E_CERT_ID\",
            \"studentID\": \"e2e-student@techpulse.demo\",
            \"studentName\": \"E2E Test Student\",
            \"courseID\": \"E2E-101\",
            \"courseName\": \"E2E Validation Course\",
            \"issueDate\": \"$(date +%Y-%m-%d)\",
            \"expiryDate\": \"2028-12-31\"
        }" -o /tmp/e2e-issue.json -w "%{http_code}" 2>/dev/null || echo "000")

    if [ "$ISSUE_HTTP" = "201" ] || [ "$ISSUE_HTTP" = "200" ]; then
        record_pass "Certificate issuance (HTTP $ISSUE_HTTP)"
    else
        record_fail "Certificate issuance (HTTP $ISSUE_HTTP)"
    fi

    # Verify the certificate
    echo "  Verifying certificate..."
    sleep 3  # Allow ledger propagation
    VERIFY_RESULT=$(curl -sS -k "https://verify-api-certchain.${DOMAIN_SUFFIX}/api/v1/verify/$E2E_CERT_ID" 2>/dev/null)
    VERIFY_STATUS=$(echo "$VERIFY_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

    if [ "$VERIFY_STATUS" = "ACTIVE" ] || [ "$VERIFY_STATUS" = "VALID" ]; then
        record_pass "Certificate verification (status: $VERIFY_STATUS)"
    else
        record_fail "Certificate verification (status: $VERIFY_STATUS, expected ACTIVE)"
    fi

    # Revoke the certificate
    echo "  Revoking certificate..."
    REVOKE_HTTP=$(curl -sS -k -X PUT \
        "https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}/api/v1/certificates/$E2E_CERT_ID/revoke" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"reason": "E2E validation test"}' \
        -o /tmp/e2e-revoke.json -w "%{http_code}" 2>/dev/null || echo "000")

    if [ "$REVOKE_HTTP" = "200" ] || [ "$REVOKE_HTTP" = "204" ]; then
        record_pass "Certificate revocation (HTTP $REVOKE_HTTP)"
    else
        record_fail "Certificate revocation (HTTP $REVOKE_HTTP)"
    fi

    # Re-verify (should be REVOKED)
    echo "  Re-verifying (expect REVOKED)..."
    sleep 3
    VERIFY2_RESULT=$(curl -sS -k "https://verify-api-certchain.${DOMAIN_SUFFIX}/api/v1/verify/$E2E_CERT_ID" 2>/dev/null)
    VERIFY2_STATUS=$(echo "$VERIFY2_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

    if [ "$VERIFY2_STATUS" = "REVOKED" ]; then
        record_pass "Post-revocation verification (status: REVOKED)"
    else
        record_fail "Post-revocation verification (status: $VERIFY2_STATUS, expected REVOKED)"
    fi

    # Cross-org verification — central verify-api can verify certs from any org
    # because each peer has the full channel ledger
    echo "  Testing cross-org verification..."
    CROSS_RESULT=$(curl -sS -k "https://verify-api-certchain.${DOMAIN_SUFFIX}/api/v1/verify/TP-FSWD-001" 2>/dev/null)
    CROSS_STATUS=$(echo "$CROSS_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
    if [ "$CROSS_STATUS" = "ACTIVE" ] || [ "$CROSS_STATUS" = "VALID" ]; then
        record_pass "Cross-org verification (seeded cert TP-FSWD-001: $CROSS_STATUS)"
    elif [ "$CROSS_STATUS" = "UNKNOWN" ] || [ "$CROSS_STATUS" = "NOT_FOUND" ]; then
        record_skip "Cross-org verification (seeded certs not found — seed script may not have run)"
    else
        record_fail "Cross-org verification (status: $CROSS_STATUS, expected ACTIVE)"
    fi

    # Transcript endpoint requires auth
    echo "  Testing transcript endpoint auth..."
    TRANSCRIPT_HTTP=$(curl -sS -k -o /dev/null -w "%{http_code}" --connect-timeout 10 \
        "https://verify-api-certchain.${DOMAIN_SUFFIX}/api/v1/transcript" 2>/dev/null || echo "000")
    if [ "$TRANSCRIPT_HTTP" = "401" ] || [ "$TRANSCRIPT_HTTP" = "403" ]; then
        record_pass "Transcript endpoint requires authentication (HTTP $TRANSCRIPT_HTTP)"
    else
        record_fail "Transcript endpoint accessible without auth (HTTP $TRANSCRIPT_HTTP)"
    fi

    # Public verification hides private fields (grade/degree)
    echo "  Testing public verification privacy..."
    PUB_GRADE=$(echo "$CROSS_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('grade','') or '')" 2>/dev/null || echo "")
    if [ -z "$PUB_GRADE" ]; then
        record_pass "Public verification hides private fields (grade not exposed)"
    elif [ "$CROSS_STATUS" = "NOT_FOUND" ] || [ "$CROSS_STATUS" = "UNKNOWN" ]; then
        record_skip "Public privacy check (seeded certs not found)"
    else
        record_fail "Public verification exposes private fields (grade: $PUB_GRADE)"
    fi
fi

# ============================================================================
# Phase 9: Monitoring Tests
# ============================================================================
banner "Phase 9: Validate Monitoring Stack"

echo "  Checking ServiceMonitors..."
SM_CENTRAL=$(oc get servicemonitors -n certchain --no-headers 2>/dev/null | wc -l | tr -d ' ')
SM_TP=$(oc get servicemonitors -n certchain-techpulse --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$SM_CENTRAL" -gt 0 ]; then
    record_pass "ServiceMonitors in certchain ($SM_CENTRAL found)"
else
    record_fail "No ServiceMonitors in certchain"
fi

if [ "$SM_TP" -gt 0 ]; then
    record_pass "ServiceMonitors in certchain-techpulse ($SM_TP found)"
else
    record_fail "No ServiceMonitors in certchain-techpulse"
fi

echo "  Checking Grafana..."
GRAFANA_HOST=$(oc get route -n certchain -l app.kubernetes.io/name=grafana \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
if [ -n "$GRAFANA_HOST" ]; then
    GRAFANA_HTTP=$(curl -sS -k -o /dev/null -w "%{http_code}" --connect-timeout 10 \
        "https://$GRAFANA_HOST" 2>/dev/null || echo "000")
    if [ "$GRAFANA_HTTP" = "200" ] || [ "$GRAFANA_HTTP" = "302" ]; then
        record_pass "Grafana reachable (HTTP $GRAFANA_HTTP)"
    else
        record_fail "Grafana returned HTTP $GRAFANA_HTTP"
    fi
else
    record_skip "Grafana route not found (may still be deploying)"
fi

echo "  Checking Quarkus metrics endpoints..."
METRICS_HTTP=$(curl -sS -k -o /dev/null -w "%{http_code}" --connect-timeout 10 \
    "https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}/q/metrics" 2>/dev/null || echo "000")
if [ "$METRICS_HTTP" = "200" ]; then
    # Check for custom counters
    HAS_COUNTER=$(curl -sS -k "https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}/q/metrics" 2>/dev/null \
        | grep -c "certificate_issued" || echo "0")
    if [ "$HAS_COUNTER" -gt 0 ]; then
        record_pass "Custom certificate metrics present"
    else
        record_fail "Metrics endpoint works but no certificate_issued counter"
    fi
else
    record_fail "Metrics endpoint not accessible (HTTP $METRICS_HTTP)"
fi

echo "  Checking user workload monitoring..."
UWM_PODS=$(oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$UWM_PODS" -gt 0 ]; then
    record_pass "User workload monitoring pods running ($UWM_PODS pods)"
else
    record_fail "No user workload monitoring pods found"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║          E2E Validation Summary                       ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  Results:"
for r in "${RESULTS[@]}"; do
    echo -e "    $r"
done
echo ""
echo -e "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Skipped: $SKIP${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}All tests passed! ✓${NC}"
    echo ""
    echo "  Next steps:"
    echo "    • Capture screenshots by opening each URL in a browser"
    echo "    • Save to media/screenshots/ and uncomment image refs in README.md"
    echo "    • Run ./scripts/demo-walkthrough.sh for the interactive demo"
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}$FAIL test(s) failed.${NC}"
    echo "  Review the failures above and check pod logs for details."
    echo ""
    exit 1
fi
