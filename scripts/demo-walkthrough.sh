#!/usr/bin/env bash
# demo-walkthrough.sh — Interactive demo walkthrough for CertChain.
# Demonstrates multi-org architecture with three personas:
#   1. Org registrar (admin) — issues/revokes certs via branded course-manager-ui
#   2. Employer (anonymous) — verifies cert via CertChain Portal
#   3. Student (authenticated) — views full transcript via identity brokering
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
API_TECHPULSE="https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}"
VERIFY_API="https://verify-api-certchain.${DOMAIN_SUFFIX}"
CERT_PORTAL="https://cert-portal-certchain.${DOMAIN_SUFFIX}"
ADMINUI_TECHPULSE="https://course-manager-ui-certchain-techpulse.${DOMAIN_SUFFIX}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CERT_ID="DEMO-TP-$(date +%Y%m%d)-001"
TIMESTAMP=$(date +%s)

pause() {
    echo ""
    echo -e "${YELLOW}  Press Enter to continue...${NC}"
    read -r
}

banner() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║   CertChain — Blockchain Certificate Credentialing    ║"
echo "  ║           Multi-Org Demo Walkthrough                  ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  This walkthrough demonstrates the full certificate lifecycle"
echo "  with three personas and per-org architecture:"
echo ""
echo "    ${BOLD}Persona 1: Org Registrar (TechPulse Academy)${NC}"
echo "      → Authenticates via TechPulse Keycloak"
echo "      → Issues a certificate via TechPulse course-manager-ui"
echo ""
echo "    ${BOLD}Persona 2: Employer (Anonymous)${NC}"
echo "      → Visits CertChain Portal (no login)"
echo "      → Verifies cert — sees basic info (valid/revoked, name, course)"
echo ""
echo "    ${BOLD}Persona 3: Student (Authenticated via Identity Brokering)${NC}"
echo "      → Logs into CertChain Portal → enters email"
echo "      → Central KC routes to TechPulse KC (email domain matching)"
echo "      → Sees full transcript with all certs and course details"
echo ""
echo -e "  ${BOLD}URLs:${NC}"
echo "    TechPulse Course Manager:  $ADMINUI_TECHPULSE"
echo "    TechPulse Keycloak:  $KC_TECHPULSE"
echo "    CertChain Portal:    $CERT_PORTAL"
echo "    Central Keycloak:    $KC_CENTRAL"
echo ""
echo -e "  ${BOLD}Demo Users:${NC}"
echo "    TechPulse registrar:  admin@techpulse.demo / admin"
echo "    TechPulse student:    student01@techpulse.demo / student"
echo ""
echo -e "  Certificate ID for this demo: ${GREEN}$CERT_ID${NC}"
pause

# ============================================================================
# Step 1: Authenticate as TechPulse registrar (via org KC)
# ============================================================================
banner "Step 1: Authenticate as TechPulse Registrar"
echo ""
echo "  The registrar logs into the TechPulse-branded course-manager-ui."
echo "  Authentication goes to TechPulse's own Keycloak instance."
echo ""
echo "    KC URL:   $KC_TECHPULSE"
echo "    Realm:    techpulse"
echo "    Client:   course-manager-ui"
echo "    User:     admin@techpulse.demo (role: org-admin)"
echo ""

TOKEN=$(curl -sS -k "$KC_TECHPULSE/realms/techpulse/protocol/openid-connect/token" \
    -d "client_id=course-manager-ui" \
    -d "username=admin@techpulse.demo" \
    -d "password=admin" \
    -d "grant_type=password" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    echo -e "  ${GREEN}✓ Authentication successful via TechPulse KC${NC}"
    echo "    Token: ${TOKEN:0:50}..."
    echo ""
    echo "  The JWT contains: org_id=techpulse, org_name=TechPulse Academy,"
    echo "  role=org-admin. The token is only valid for TechPulse's cert-admin-api."
else
    echo -e "  ${RED}✗ Authentication failed${NC}"
    echo "  Check that TechPulse Keycloak is running at $KC_TECHPULSE"
    exit 1
fi
pause

# ============================================================================
# Step 2: View TechPulse dashboard
# ============================================================================
banner "Step 2: View TechPulse Dashboard"
echo ""
echo "  Calling: GET $API_TECHPULSE/api/v1/dashboard/stats"
echo "  (uses TechPulse's own cert-admin-api instance)"
echo ""

STATS=$(curl -sS -k -H "Authorization: Bearer $TOKEN" "$API_TECHPULSE/api/v1/dashboard/stats" 2>/dev/null)
echo "$STATS" | python3 -c "
import sys, json
s = json.load(sys.stdin)
print(f\"  Total Certificates:  {s.get('totalCerts', 0)}\")
print(f\"  Active:              {s.get('activeCerts', 0)}\")
print(f\"  Revoked:             {s.get('revokedCerts', 0)}\")
print(f\"  Expired:             {s.get('expiredCerts', 0)}\")
" 2>/dev/null
pause

# ============================================================================
# Step 3: Issue a new certificate
# ============================================================================
banner "Step 3: Issue a New Certificate"
echo ""
echo "  Issuing certificate: $CERT_ID"
echo "    Student:  Jane Doe (student01@techpulse.demo)"
echo "    Course:   Full-Stack Web Dev (FSWD-101)"
echo "    Dates:    $(date +%Y-%m-%d) → 2028-12-31"
echo ""
echo "  This writes a transaction to the Hyperledger Fabric ledger via"
echo "  TechPulse's peer (peer0-techpulse). Composite key: CERT~techpulse~$CERT_ID"
echo ""

ISSUE_DATE=$(date +%Y-%m-%d)
HTTP=$(curl -sS -k -X POST "$API_TECHPULSE/api/v1/certificates" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"certID\": \"$CERT_ID\",
        \"studentID\": \"student01\",
        \"studentName\": \"Jane Doe\",
        \"courseID\": \"FSWD-101\",
        \"courseName\": \"Full-Stack Web Dev\",
        \"issueDate\": \"$ISSUE_DATE\",
        \"expiryDate\": \"2028-12-31\"
    }" -o /tmp/certchain-demo-issue.json -w "%{http_code}" 2>/dev/null)

if [ "$HTTP" = "201" ] || [ "$HTTP" = "200" ]; then
    echo -e "  ${GREEN}✓ Certificate issued successfully (HTTP $HTTP)${NC}"
    echo ""
    echo "  Response:"
    python3 -c "
import json
d = json.load(open('/tmp/certchain-demo-issue.json'))
for k, v in d.items():
    if v: print(f'    {k:15s}: {v}')
" 2>/dev/null
else
    echo -e "  ${RED}✗ Issue failed (HTTP $HTTP)${NC}"
    cat /tmp/certchain-demo-issue.json 2>/dev/null
fi
pause

# ============================================================================
# Step 4: Employer verifies (anonymous — CertChain Portal)
# ============================================================================
banner "Step 4: Employer Verifies Certificate (Anonymous)"
echo ""
echo "  An employer visits the CertChain Portal — no login required."
echo "  They enter the cert ID or scan a QR code."
echo ""
echo "  Portal: $CERT_PORTAL/result/$CERT_ID"
echo "  API:    GET $VERIFY_API/api/v1/verify/$CERT_ID"
echo ""
echo "  The employer sees basic info only:"
echo "    • Valid/Revoked status"
echo "    • Student name, course name, issuing org, dates"
echo ""

sleep 2
VERIFY=$(curl -sS -k "$VERIFY_API/api/v1/verify/$CERT_ID" 2>/dev/null)
echo "$VERIFY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
status = d.get('status', 'UNKNOWN')
color = '\033[0;32m' if status in ('VALID', 'ACTIVE') else '\033[0;31m'
print(f\"  Status: {color}{status}\033[0m\")
print()
for k in ['studentName', 'courseName', 'orgName', 'issueDate', 'expiryDate']:
    if k in d and d[k]:
        label = k.replace('Name', ' Name').replace('Date', ' Date').replace('org', 'Org').title()
        print(f'    {label:15s}: {d[k]}')
" 2>/dev/null
pause

# ============================================================================
# Step 5: Student login via identity brokering (concept)
# ============================================================================
banner "Step 5: Student Login via Identity Brokering"
echo ""
echo "  A student visits the same CertChain Portal and clicks 'Login'."
echo "  The login flow uses Keycloak Identity Brokering:"
echo ""
echo "    1. Student clicks 'Login' → redirected to Central KC"
echo "    2. Central KC login page asks for email only"
echo "    3. Student enters: student01@techpulse.demo"
echo "    4. KC Organizations detects domain 'techpulse.demo'"
echo "    5. Auto-redirect to TechPulse KC (no IDP chooser!)"
echo "    6. Student enters password at TechPulse KC"
echo "    7. Redirect back → Central KC JIT-creates user under TechPulse Org"
echo "    8. Student is now logged in with a central KC token"
echo ""
echo "  After login, the student sees a 'My Transcript' tab with:"
echo "    • All certificates across all orgs"
echo "    • Detailed course info, grades, graduation details"
echo "    • Downloadable/shareable transcript"
echo ""
echo "  ${BOLD}Try it:${NC} $CERT_PORTAL → Login → student01@techpulse.demo / student"
pause

# ============================================================================
# Step 6: Revoke the certificate
# ============================================================================
banner "Step 6: Revoke the Certificate"
echo ""
echo "  The TechPulse registrar revokes the certificate."
echo "  This is an irreversible blockchain transaction."
echo ""
echo "  Calling: PUT $API_TECHPULSE/api/v1/certificates/$CERT_ID/revoke"
echo ""

HTTP=$(curl -sS -k -X PUT "$API_TECHPULSE/api/v1/certificates/$CERT_ID/revoke" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"reason": "Demo walkthrough — academic policy violation"}' \
    -o /tmp/certchain-demo-revoke.json -w "%{http_code}" 2>/dev/null)

if [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ]; then
    echo -e "  ${GREEN}✓ Certificate revoked (HTTP $HTTP)${NC}"
    echo ""
    echo "  Revocation is now permanently recorded on the Fabric ledger."
else
    echo -e "  ${RED}✗ Revoke failed (HTTP $HTTP)${NC}"
    cat /tmp/certchain-demo-revoke.json 2>/dev/null
fi
pause

# ============================================================================
# Step 7: Re-verify (should show REVOKED)
# ============================================================================
banner "Step 7: Re-verify (Expect REVOKED)"
echo ""
echo "  The employer re-checks the same certificate..."
echo ""

sleep 2
VERIFY=$(curl -sS -k "$VERIFY_API/api/v1/verify/$CERT_ID" 2>/dev/null)
echo "$VERIFY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
status = d.get('status', 'UNKNOWN')
color = '\033[0;31m' if status == 'REVOKED' else '\033[0;33m'
print(f\"  Status: {color}{status}\033[0m\")
reason = d.get('revokeReason', '')
if reason:
    print(f'  Reason: {reason}')
" 2>/dev/null

echo ""
echo "  The certificate now shows as REVOKED to everyone."
pause

# ============================================================================
# Finish
# ============================================================================
echo ""
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║              Demo Walkthrough Complete!                ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  Key takeaways:"
echo "    • Each org has its own Keycloak, course-manager-ui, and cert-admin-api"
echo "    • Certificates are anchored to Hyperledger Fabric (immutable)"
echo "    • CertChain Portal serves both anonymous and authenticated users"
echo "    • Identity brokering routes students to their org's KC automatically"
echo "    • Revocation is permanent and auditable across all orgs"
echo ""
echo "  Try the UIs:"
echo "    TechPulse Course Manager:  $ADMINUI_TECHPULSE"
echo "    CertChain Portal:     $CERT_PORTAL"
echo "    Central KC Console:   $KC_CENTRAL"
echo ""
echo "  Run the full E2E test suite:"
echo "    ./scripts/test-end-to-end.sh"
echo ""
