#!/usr/bin/env bash
# resilience-demo.sh — Demonstrates CertChain resilience and self-healing.
# Shows pod failure recovery and chain resilience across namespaces.
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

VERIFY_API="https://verify-api-certchain.${DOMAIN_SUFFIX}"
CERT_ADMIN_API_TP="https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pause() { echo ""; echo -e "${YELLOW}  Press Enter to continue...${NC}"; read -r; }
banner() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

wait_for_pod() {
    local ns=$1 label=$2 timeout=${3:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        ready=$(oc -n "$ns" get pod -l "$label" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        if [ "$ready" = "True" ]; then
            echo -e "  ${GREEN}✓ Pod recovered ($elapsed seconds)${NC}"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed+1))
        if [ $((elapsed % 5)) -eq 0 ]; then
            echo -e "  ${YELLOW}⏳ Waiting for recovery... ($elapsed seconds)${NC}"
        fi
    done
    echo -e "  ${RED}✗ Pod did not recover within ${timeout}s${NC}"
    return 1
}

# Title
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║   CertChain — Resilience & Self-Healing Demo          ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  This demo shows three resilience scenarios:"
echo "    1. Pod self-healing (kill + auto-recovery)"
echo "    2. Multi-org isolation (one org failure, others unaffected)"
echo "    3. Chain resilience (verify without central services)"
echo ""
echo "  Prerequisites:"
echo "    - At least one certificate issued (run: make seed)"
echo "    - TechPulse verification instance deployed"
pause

# ============================================================================
# Part 1: Pod Self-Healing
# ============================================================================
banner "Part 1: Pod Self-Healing"
echo ""
echo "  Kubernetes automatically restarts failed pods."
echo "  We'll kill the CouchDB pod and watch it recover."
echo ""

echo "  Current pod status:"
oc -n certchain-techpulse get pods -l app=couchdb,org=techpulse --no-headers 2>/dev/null || true
pause

echo ""
echo -e "  ${RED}Killing couchdb-techpulse pod...${NC}"
oc -n certchain-techpulse delete pod -l app=couchdb,org=techpulse --grace-period=0 --force 2>/dev/null || true

echo ""
echo "  Watching recovery..."
wait_for_pod "certchain-techpulse" "app=couchdb,org=techpulse" 60

echo ""
echo "  Final pod status:"
oc -n certchain-techpulse get pods -l app=couchdb,org=techpulse --no-headers 2>/dev/null || true
pause

# ============================================================================
# Part 2: Multi-Org Isolation
# ============================================================================
banner "Part 2: Multi-Org Isolation"
echo ""
echo "  Each org runs in its own namespace."
echo "  Killing TechPulse's cert-admin-api should NOT affect DataForge."
echo ""

echo -e "  ${RED}Killing cert-admin-api in TechPulse namespace...${NC}"
oc -n certchain-techpulse delete pod -l app=cert-admin-api,org=techpulse --grace-period=0 --force 2>/dev/null || true
sleep 2

echo ""
echo "  Testing DataForge cert-admin-api (should still work)..."
DF_STATUS=$(curl -sS -k -o /dev/null -w "%{http_code}" "https://cert-admin-api-certchain-dataforge.${DOMAIN_SUFFIX}/q/health/ready" 2>/dev/null || echo "000")
if [ "$DF_STATUS" = "200" ]; then
    echo -e "  ${GREEN}✓ DataForge cert-admin-api is healthy (HTTP $DF_STATUS)${NC}"
else
    echo -e "  ${YELLOW}⚠ DataForge returned HTTP $DF_STATUS (may still be starting)${NC}"
fi

echo ""
echo "  Waiting for TechPulse cert-admin-api recovery..."
wait_for_pod "certchain-techpulse" "app=cert-admin-api,org=techpulse" 60
pause

# ============================================================================
# Part 3: Chain Resilience
# ============================================================================
banner "Part 3: Orderer Resilience (Reads vs Writes)"
echo ""
echo "  This demonstrates the key blockchain value proposition:"
echo "  READ operations (verification) work without the orderer."
echo "  Only WRITE operations (issuance) require the orderer."
echo ""
echo "  How it works:"
echo "    - Each peer has a full copy of the ledger"
echo "    - verify-api reads from the peer's local ledger (no orderer)"
echo "    - cert-admin-api writes go through the orderer cluster"
echo ""
echo "  We'll stop the central orderer, then show that:"
echo "    ✓ Verification still works (reads from peer)"
echo "    ✗ Issuance fails (needs orderer for consensus)"
pause

# Get a cert ID
echo "  Finding a certificate to verify..."
CERT_ID="TP-2026-001"
echo "  Using certificate: $CERT_ID"

echo ""
echo "  Step 1: Verify certificate (baseline)..."
C_HTTP=$(curl -sS -k -o /dev/null -w "%{http_code}" "$VERIFY_API/api/v1/verify/$CERT_ID" 2>/dev/null || echo "000")
echo -e "  verify-api: HTTP $C_HTTP"
pause

echo ""
echo -e "  ${RED}Step 2: Stopping central orderer...${NC}"
echo "    Scaling orderer0 to 0 replicas..."
oc -n certchain scale deployment orderer0 --replicas=0 2>/dev/null || true
sleep 5

echo ""
echo "  Step 3: Verification STILL WORKS (read-only, no orderer needed)..."
V_HTTP=$(curl -sS -k -o /dev/null -w "%{http_code}" --connect-timeout 10 "$VERIFY_API/api/v1/verify/$CERT_ID" 2>/dev/null || echo "000")
if [ "$V_HTTP" = "200" ]; then
    echo -e "  ${GREEN}✓ verify-api: OPERATIONAL (HTTP $V_HTTP) — reads from peer's local ledger${NC}"
    RESULT=$(curl -sS -k "$VERIFY_API/api/v1/verify/$CERT_ID" 2>/dev/null)
    echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
status = d.get('status', 'UNKNOWN')
color = '\033[0;32m' if status in ('VALID','ACTIVE') else '\033[0;31m'
print(f'  Certificate status: {color}{status}\033[0m')
print(f'  Student: {d.get(\"studentName\",\"N/A\")}')
print(f'  Course: {d.get(\"courseName\",\"N/A\")}')
" 2>/dev/null || true
else
    echo -e "  ${YELLOW}⚠ verify-api returned HTTP $V_HTTP (may need more time)${NC}"
fi
pause

echo ""
echo -e "  ${GREEN}Step 4: Restoring central orderer...${NC}"
oc -n certchain scale deployment orderer0 --replicas=1 2>/dev/null || true

echo "  Waiting for orderer recovery..."
wait_for_pod "certchain" "app=orderer" 90

echo ""
echo -e "  ${GREEN}✓ Central orderer restored — writes operational again${NC}"
pause

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║          Resilience Demo Complete!                     ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  Key takeaways:"
echo "    ${GREEN}✓${NC} Pods self-heal automatically via Kubernetes"
echo "    ${GREEN}✓${NC} Multi-org isolation — one org's failure doesn't affect others"
echo "    ${GREEN}✓${NC} Blockchain resilience — verification works without the orderer"
echo "    ${GREEN}✓${NC} Each peer has a full ledger copy (read-only queries are local)"
echo "    ${GREEN}✓${NC} Only write operations (issuance/revocation) require the orderer"
echo ""
