#!/usr/bin/env bash
# test-end-to-end.sh — End-to-end test exercising the full certificate lifecycle
# across all three organizations (TechPulse, DataForge, NeuralPath).
# Tests multi-org architecture: per-org KC, per-org API, identity brokering,
# cross-org isolation, and two-tier verification (anonymous + authenticated).
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

# --- Per-org URLs ---
KC_CENTRAL="https://keycloak-certchain.${DOMAIN_SUFFIX}"
KC_TECHPULSE="https://keycloak-certchain-techpulse.${DOMAIN_SUFFIX}"
KC_DATAFORGE="https://keycloak-certchain-dataforge.${DOMAIN_SUFFIX}"
KC_NEURALPATH="https://keycloak-certchain-neuralpath.${DOMAIN_SUFFIX}"

API_TECHPULSE="https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}"
API_DATAFORGE="https://cert-admin-api-certchain-dataforge.${DOMAIN_SUFFIX}"
API_NEURALPATH="https://cert-admin-api-certchain-neuralpath.${DOMAIN_SUFFIX}"

VERIFY_API="https://verify-api-certchain.${DOMAIN_SUFFIX}"
CERT_PORTAL="https://cert-portal-certchain.${DOMAIN_SUFFIX}"

ADMINUI_TECHPULSE="https://course-manager-ui-certchain-techpulse.${DOMAIN_SUFFIX}"
ADMINUI_DATAFORGE="https://course-manager-ui-certchain-dataforge.${DOMAIN_SUFFIX}"
ADMINUI_NEURALPATH="https://course-manager-ui-certchain-neuralpath.${DOMAIN_SUFFIX}"

PASS=0
FAIL=0
TOTAL=0
TIMESTAMP=$(date +%s)
CURL_OPTS="--connect-timeout 10 --max-time 30"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC}: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo -e "  ${RED}FAIL${NC}: $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }
info() { echo -e "  ${BLUE}INFO${NC}: $1"; }
section() { echo -e "\n${YELLOW}━━━ $1 ━━━${NC}"; }

# --- Authenticate against an org KC ---
# Usage: get_org_token <kc_url> <realm> <client_id> <username> <password>
get_org_token() {
    local kc_url="$1" realm="$2" client_id="$3" username="$4" password="$5"
    curl -sS -k $CURL_OPTS "$kc_url/realms/$realm/protocol/openid-connect/token" \
        -d "client_id=$client_id" \
        -d "username=$username" \
        -d "password=$password" \
        -d "grant_type=password" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo ""
}

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     CertChain End-to-End Test Suite      ║${NC}"
echo -e "${BLUE}║        Multi-Org Architecture            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Central KC:   $KC_CENTRAL"
echo "  Verify API:   $VERIFY_API"
echo "  Cert Portal:  $CERT_PORTAL"
echo "  TechPulse:    KC=$KC_TECHPULSE  API=$API_TECHPULSE"
echo "  DataForge:    KC=$KC_DATAFORGE  API=$API_DATAFORGE"
echo "  NeuralPath:   KC=$KC_NEURALPATH  API=$API_NEURALPATH"
echo "  Timestamp:    $TIMESTAMP"

# --- Org configuration ---
ORG_KEYS=("techpulse" "dataforge" "neuralpath")
ORG_USERS=("admin@techpulse.demo" "admin@dataforge.demo" "admin@neuralpath.demo")
ORG_DISPLAY=("TechPulse Academy" "DataForge Institute" "NeuralPath Labs")
ORG_COURSE_IDS=("FSWD-101" "PGA-101" "AML-101")
ORG_COURSE_NAMES=("Full-Stack Web Dev" "PostgreSQL Administration" "Applied Machine Learning")
ORG_KC_URLS=("$KC_TECHPULSE" "$KC_DATAFORGE" "$KC_NEURALPATH")
ORG_KC_REALMS=("techpulse" "dataforge" "neuralpath")
ORG_API_URLS=("$API_TECHPULSE" "$API_DATAFORGE" "$API_NEURALPATH")
ORG_ADMINUI_URLS=("$ADMINUI_TECHPULSE" "$ADMINUI_DATAFORGE" "$ADMINUI_NEURALPATH")

# Token storage
TOKEN_0=""
TOKEN_1=""
TOKEN_2=""

# ============================================================================
# Test 1: Platform connectivity
# ============================================================================
section "1. Platform Connectivity"

# Central services
for url in "$CERT_PORTAL" "$KC_CENTRAL/realms/certchain" "$VERIFY_API/q/health"; do
    HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    name=$(echo "$url" | sed "s|https://||" | cut -d'.' -f1)
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
        pass "$name reachable (HTTP $HTTP)"
    else
        fail "$name unreachable (HTTP $HTTP)"
    fi
done

# Per-org services
for i in 0 1 2; do
    org="${ORG_KEYS[$i]}"
    for url in "${ORG_KC_URLS[$i]}/realms/${ORG_KC_REALMS[$i]}" "${ORG_API_URLS[$i]}/q/health" "${ORG_ADMINUI_URLS[$i]}"; do
        HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        name="$org/$(echo "$url" | sed "s|https://||" | sed "s|\..*||" | sed "s|.*-||")"
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
            pass "$name reachable (HTTP $HTTP)"
        else
            fail "$name unreachable (HTTP $HTTP)"
        fi
    done
done

# ============================================================================
# Test 2: Per-org authentication
# ============================================================================
section "2. Per-Org Authentication (Keycloak OIDC)"

for i in 0 1 2; do
    user="${ORG_USERS[$i]}"
    display="${ORG_DISPLAY[$i]}"
    kc_url="${ORG_KC_URLS[$i]}"
    realm="${ORG_KC_REALMS[$i]}"
    TOKEN=$(get_org_token "$kc_url" "$realm" "course-manager-ui" "$user" "admin")
    if [ -n "$TOKEN" ]; then
        eval "TOKEN_$i=\"$TOKEN\""
        pass "$display admin authenticated via $realm KC ($user)"
    else
        fail "$display admin authentication failed ($user @ $kc_url)"
    fi
done

# ============================================================================
# Test 3: Dashboard stats for each org
# ============================================================================
section "3. Dashboard Stats (per-org API)"

for i in 0 1 2; do
    display="${ORG_DISPLAY[$i]}"
    api_url="${ORG_API_URLS[$i]}"
    eval "TOKEN=\$TOKEN_$i"
    if [ -z "$TOKEN" ]; then
        fail "$display dashboard — no token"
        continue
    fi
    HTTP=$(curl -sS -k $CURL_OPTS -o /tmp/certchain-e2e-stats.json -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "$api_url/api/v1/dashboard/stats" 2>/dev/null)
    if [ "$HTTP" = "200" ]; then
        total=$(python3 -c "import json; d=json.load(open('/tmp/certchain-e2e-stats.json')); print(d.get('totalCerts',0))" 2>/dev/null || echo "?")
        pass "$display dashboard stats via own API (total: $total)"
    else
        fail "$display dashboard stats (HTTP $HTTP)"
    fi
done

# ============================================================================
# Test 4: Full certificate lifecycle per org
# ============================================================================
section "4. Certificate Lifecycle (Issue → Verify → Revoke → Re-verify)"

for i in 0 1 2; do
    org="${ORG_KEYS[$i]}"
    display="${ORG_DISPLAY[$i]}"
    api_url="${ORG_API_URLS[$i]}"
    eval "TOKEN=\$TOKEN_$i"
    CERT_ID="E2E-${org}-$TIMESTAMP"
    COURSE_ID="${ORG_COURSE_IDS[$i]}"
    COURSE_NAME="${ORG_COURSE_NAMES[$i]}"

    echo ""
    info "$display — cert $CERT_ID via $api_url"

    if [ -z "$TOKEN" ]; then
        fail "$org — no token, skipping lifecycle"
        continue
    fi

    # 4a. Issue via per-org API
    ISSUE_DATE=$(date +%Y-%m-%d)
    HTTP=$(curl -sS -k $CURL_OPTS -X POST "$api_url/api/v1/certificates" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"certID\": \"$CERT_ID\",
            \"studentID\": \"e2e-student-$i@${org}.demo\",
            \"studentName\": \"E2E Student $org\",
            \"courseID\": \"$COURSE_ID\",
            \"courseName\": \"$COURSE_NAME\",
            \"issueDate\": \"$ISSUE_DATE\",
            \"expiryDate\": \"2028-12-31\"
        }" -o /tmp/certchain-e2e-issue.json -w "%{http_code}" 2>/dev/null)

    if [ "$HTTP" = "201" ] || [ "$HTTP" = "200" ]; then
        pass "$org — issued $CERT_ID (HTTP $HTTP)"
    else
        fail "$org — issue failed (HTTP $HTTP): $(cat /tmp/certchain-e2e-issue.json 2>/dev/null)"
        continue
    fi

    # 4b. Verify (public API, no auth)
    sleep 2
    VERIFY_JSON=$(curl -sS -k $CURL_OPTS "$VERIFY_API/api/v1/verify/$CERT_ID" 2>/dev/null)
    STATUS=$(echo "$VERIFY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")

    if [ "$STATUS" = "VALID" ] || [ "$STATUS" = "ACTIVE" ]; then
        pass "$org — verify returned $STATUS"
    else
        fail "$org — verify expected VALID, got $STATUS"
    fi

    # 4c. Revoke via per-org API
    HTTP=$(curl -sS -k $CURL_OPTS -X PUT "$api_url/api/v1/certificates/$CERT_ID/revoke" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"reason\": \"E2E test revocation for $org\"}" \
        -o /tmp/certchain-e2e-revoke.json -w "%{http_code}" 2>/dev/null)

    if [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ]; then
        pass "$org — revoked $CERT_ID (HTTP $HTTP)"
    else
        fail "$org — revoke failed (HTTP $HTTP)"
    fi

    # 4d. Re-verify (expect REVOKED)
    sleep 2
    VERIFY_JSON=$(curl -sS -k $CURL_OPTS "$VERIFY_API/api/v1/verify/$CERT_ID" 2>/dev/null)
    STATUS=$(echo "$VERIFY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")

    if [ "$STATUS" = "REVOKED" ]; then
        pass "$org — re-verify returned REVOKED"
    else
        fail "$org — re-verify expected REVOKED, got $STATUS"
    fi
done

# ============================================================================
# Test 5: Courses endpoint per org
# ============================================================================
section "5. Courses Endpoint (per-org API)"

for i in 0 1 2; do
    display="${ORG_DISPLAY[$i]}"
    api_url="${ORG_API_URLS[$i]}"
    eval "TOKEN=\$TOKEN_$i"
    if [ -z "$TOKEN" ]; then
        fail "$display courses — no token"
        continue
    fi
    COURSES_JSON=$(curl -sS -k $CURL_OPTS -H "Authorization: Bearer $TOKEN" "$api_url/api/v1/courses" 2>/dev/null)
    COUNT=$(echo "$COURSES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        pass "$display — $COUNT courses available"
    else
        fail "$display — no courses returned"
    fi
done

# ============================================================================
# Test 6: Cross-org isolation
# ============================================================================
section "6. Cross-Org Isolation"

# TechPulse token should fail against DataForge API
if [ -n "$TOKEN_0" ]; then
    HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN_0" \
        "$API_DATAFORGE/api/v1/certificates" 2>/dev/null)
    if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
        pass "TechPulse token rejected by DataForge API (HTTP $HTTP)"
    else
        fail "TechPulse token accepted by DataForge API (HTTP $HTTP) — isolation breach!"
    fi
fi

# DataForge token should fail against NeuralPath API
if [ -n "$TOKEN_1" ]; then
    HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN_1" \
        "$API_NEURALPATH/api/v1/certificates" 2>/dev/null)
    if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
        pass "DataForge token rejected by NeuralPath API (HTTP $HTTP)"
    else
        fail "DataForge token accepted by NeuralPath API (HTTP $HTTP) — isolation breach!"
    fi
fi

# TechPulse admin sees only TechPulse certs
if [ -n "$TOKEN_0" ]; then
    CERTS_JSON=$(curl -sS -k $CURL_OPTS -H "Authorization: Bearer $TOKEN_0" "$API_TECHPULSE/api/v1/certificates" 2>/dev/null)
    NON_TP=$(echo "$CERTS_JSON" | python3 -c "
import sys, json
certs = json.load(sys.stdin)
non_tp = [c for c in certs if c.get('orgID','') != 'techpulse']
print(len(non_tp))
" 2>/dev/null || echo "?")
    if [ "$NON_TP" = "0" ]; then
        pass "TechPulse admin sees only TechPulse certs"
    else
        fail "TechPulse admin sees $NON_TP non-TechPulse certs (isolation breach)"
    fi
fi

# ============================================================================
# Test 7: Edge cases
# ============================================================================
section "7. Edge Cases"

VERIFY_JSON=$(curl -sS -k $CURL_OPTS "$VERIFY_API/api/v1/verify/NON-EXISTENT-CERT" 2>/dev/null)
STATUS=$(echo "$VERIFY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")

if [ "$STATUS" = "NOT_FOUND" ]; then
    pass "Non-existent cert returns NOT_FOUND"
else
    fail "Non-existent cert expected NOT_FOUND, got $STATUS"
fi

# QR code endpoint
HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" "$VERIFY_API/api/v1/verify/E2E-techpulse-$TIMESTAMP/qr" 2>/dev/null)
if [ "$HTTP" = "200" ]; then
    pass "QR code endpoint returns 200"
else
    fail "QR code endpoint returned HTTP $HTTP"
fi

# Transcript endpoint without auth should fail (401/403)
HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" "$VERIFY_API/api/v1/transcript" 2>/dev/null)
if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
    pass "Transcript endpoint requires authentication (HTTP $HTTP)"
else
    fail "Transcript endpoint accessible without auth (HTTP $HTTP)"
fi

# ============================================================================
# Test 8: Admin role enforcement (students blocked from course-manager-ui API)
# ============================================================================
section "8. Admin Role Enforcement"

# Authenticate as a student
STUDENT_TOKENS=()
for i in 0 1 2; do
    org="${ORG_KEYS[$i]}"
    kc_url="${ORG_KC_URLS[$i]}"
    realm="${ORG_KC_REALMS[$i]}"
    student_users=("student01@techpulse.demo" "student03@dataforge.demo" "student05@neuralpath.demo")
    STOK=$(get_org_token "$kc_url" "$realm" "course-manager-ui" "${student_users[$i]}" "student")
    STUDENT_TOKENS+=("$STOK")
    if [ -n "$STOK" ]; then
        # Student should NOT be able to access cert-admin-api endpoints
        api_url="${ORG_API_URLS[$i]}"
        HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $STOK" \
            "$api_url/api/v1/dashboard/stats" 2>/dev/null)
        if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
            pass "$org — student blocked from cert-admin-api (HTTP $HTTP)"
        else
            fail "$org — student accessed cert-admin-api (HTTP $HTTP) — role enforcement missing!"
        fi
    else
        info "$org — could not get student token (student user may not exist)"
    fi
done

# ============================================================================
# Test 9: Certificate ownership privacy (grade/degree visibility)
# ============================================================================
section "9. Certificate Ownership Privacy"

# Get a student token from central KC for transcript access
CENTRAL_STUDENT_TOKEN=$(curl -sS -k $CURL_OPTS \
    "$KC_CENTRAL/realms/certchain/protocol/openid-connect/token" \
    -d "client_id=cert-portal" \
    -d "username=student01@techpulse.demo" \
    -d "password=student" \
    -d "grant_type=password" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [ -n "$CENTRAL_STUDENT_TOKEN" ] && [ "$CENTRAL_STUDENT_TOKEN" != "" ]; then
    pass "Central KC student authentication (student01@techpulse.demo)"

    # Student's own cert — should include grade/degree
    OWN_CERT=$(curl -sS -k $CURL_OPTS \
        -H "Authorization: Bearer $CENTRAL_STUDENT_TOKEN" \
        "$VERIFY_API/api/v1/transcript/TP-FSWD-001" 2>/dev/null)
    OWN_GRADE=$(echo "$OWN_CERT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('grade','') or '')" 2>/dev/null || echo "")

    if [ -n "$OWN_GRADE" ]; then
        pass "Owner sees private fields on own cert (grade: $OWN_GRADE)"
    else
        fail "Owner cannot see private fields on own cert (grade missing)"
    fi

    # Another student's cert — should NOT include grade/degree
    OTHER_CERT=$(curl -sS -k $CURL_OPTS \
        -H "Authorization: Bearer $CENTRAL_STUDENT_TOKEN" \
        "$VERIFY_API/api/v1/transcript/DF-PGA-001" 2>/dev/null)
    OTHER_GRADE=$(echo "$OTHER_CERT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('grade','') or '')" 2>/dev/null || echo "")

    if [ -z "$OTHER_GRADE" ]; then
        pass "Non-owner cannot see private fields on other's cert"
    else
        fail "Non-owner sees private fields on other's cert (grade: $OTHER_GRADE) — privacy breach!"
    fi
else
    info "Central KC student auth failed — skipping privacy tests (identity brokering may not be configured)"
fi

# ============================================================================
# Test 10: Central KC identity brokering (discovery only)
# ============================================================================
section "10. Central KC Identity Brokering"

# Verify central KC has identity providers configured
IDP_JSON=$(curl -sS -k $CURL_OPTS "$KC_CENTRAL/realms/certchain/.well-known/openid-configuration" 2>/dev/null)
if echo "$IDP_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'authorization_endpoint' in d" 2>/dev/null; then
    pass "Central KC certchain realm OIDC discovery OK"
else
    fail "Central KC certchain realm OIDC discovery failed"
fi

# Verify each org KC realm is accessible
for i in 0 1 2; do
    org="${ORG_KEYS[$i]}"
    kc_url="${ORG_KC_URLS[$i]}"
    realm="${ORG_KC_REALMS[$i]}"
    HTTP=$(curl -sS -k $CURL_OPTS -o /dev/null -w "%{http_code}" "$kc_url/realms/$realm/.well-known/openid-configuration" 2>/dev/null)
    if [ "$HTTP" = "200" ]; then
        pass "$org KC realm OIDC discovery OK"
    else
        fail "$org KC realm OIDC discovery failed (HTTP $HTTP)"
    fi
done

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo -e "${BLUE}║${NC}  ${RED}E2E Test Results: FAILURES DETECTED${NC}     ${BLUE}║${NC}"
else
    echo -e "${BLUE}║${NC}  ${GREEN}E2E Test Results: ALL PASSED${NC}            ${BLUE}║${NC}"
fi
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Passed: ${GREEN}$PASS${NC}"
echo -e "  Failed: ${RED}$FAIL${NC}"
echo -e "  Total:  $TOTAL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo -e "  ${GREEN}All tests passed.${NC}"
