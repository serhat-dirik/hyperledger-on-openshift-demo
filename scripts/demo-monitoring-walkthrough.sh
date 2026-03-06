#!/usr/bin/env bash
# demo-monitoring-walkthrough.sh — Interactive monitoring walkthrough for CertChain demo.
#
# Walks through the observability stack showing:
#   1. ServiceMonitor targets discovered by Prometheus
#   2. Fabric peer/orderer metrics available
#   3. Quarkus application metrics and custom counters
#   4. Grafana dashboards
#
# Usage: bash scripts/demo-monitoring-walkthrough.sh
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

CENTRAL_NS="$PROJECT_NAMESPACE"

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

pause() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

header() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD} $1${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
}

# ---- Intro ----
header "CertChain Monitoring & Observability Walkthrough"
echo "This walkthrough demonstrates the monitoring stack:"
echo "  - OpenShift User Workload Monitoring (Prometheus)"
echo "  - Fabric peer/orderer metrics"
echo "  - Quarkus Micrometer metrics with custom counters"
echo "  - Grafana dashboards"
pause

# ---- Step 1: Verify User Workload Monitoring ----
header "Step 1: User Workload Monitoring"
echo -e "${GREEN}Checking user workload monitoring pods...${NC}"
echo ""
oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | while read -r line; do
    echo "  $line"
done
echo ""
echo "User workload monitoring is enabled. OpenShift Prometheus is scraping"
echo "ServiceMonitor resources in our CertChain namespaces."
pause

# ---- Step 2: ServiceMonitors ----
header "Step 2: ServiceMonitors"
echo -e "${GREEN}ServiceMonitors across CertChain namespaces:${NC}"
echo ""
for ns in "$CENTRAL_NS" "${CENTRAL_NS}-techpulse" "${CENTRAL_NS}-dataforge" "${CENTRAL_NS}-neuralpath"; do
    monitors=$(oc get servicemonitors -n "$ns" --no-headers 2>/dev/null || echo "")
    if [ -n "$monitors" ]; then
        echo "  [$ns]"
        echo "$monitors" | while read -r line; do echo "    $line"; done
    fi
done
pause

# ---- Step 3: Fabric Metrics ----
header "Step 3: Fabric Peer Metrics"
echo -e "${GREEN}Querying metrics from a peer operations endpoint...${NC}"
echo ""

# Port-forward to a peer and grab metrics sample
PEER_POD=$(oc get pods -n "${CENTRAL_NS}-techpulse" -l app=peer --no-headers -o name 2>/dev/null | head -1)
if [ -n "$PEER_POD" ]; then
    echo "  Target: ${PEER_POD} in ${CENTRAL_NS}-techpulse"
    echo ""
    # Get a snapshot of key metrics
    oc exec -n "${CENTRAL_NS}-techpulse" "$PEER_POD" -- \
        wget -qO- http://localhost:9443/metrics 2>/dev/null \
        | grep -E "^(endorser_proposals|ledger_block|grpc_server)" \
        | head -15 || echo "  (peer not ready or metrics not yet available)"
else
    echo "  No peer pod found in ${CENTRAL_NS}-techpulse"
fi
pause

# ---- Step 4: Orderer Metrics ----
header "Step 4: Fabric Orderer Metrics"
echo -e "${GREEN}Querying metrics from an orderer operations endpoint...${NC}"
echo ""

ORDERER_POD=$(oc get pods -n "$CENTRAL_NS" -l app=orderer --no-headers -o name 2>/dev/null | head -1)
if [ -n "$ORDERER_POD" ]; then
    echo "  Target: ${ORDERER_POD} in ${CENTRAL_NS}"
    echo ""
    oc exec -n "$CENTRAL_NS" "$ORDERER_POD" -- \
        wget -qO- http://localhost:8443/metrics 2>/dev/null \
        | grep -E "^(consensus_|broadcast_|grpc_server)" \
        | head -15 || echo "  (orderer not ready or metrics not yet available)"
else
    echo "  No orderer pod found in ${CENTRAL_NS}"
fi
pause

# ---- Step 5: Quarkus Application Metrics ----
header "Step 5: Quarkus Application Metrics"
echo -e "${GREEN}Custom certificate counters from cert-admin-api:${NC}"
echo ""

ADMIN_ROUTE="https://cert-admin-api-${CENTRAL_NS}-techpulse.${DOMAIN_SUFFIX}"
curl -sk "${ADMIN_ROUTE}/q/metrics" 2>/dev/null \
    | grep -E "^certificate_(issued|revoked)" \
    | head -10 || echo "  (cert-admin-api not ready — try seeding certificates first)"

echo ""
echo -e "${GREEN}Custom certificate counters from verify-api:${NC}"
echo ""

VERIFY_ROUTE="https://verify-api-${CENTRAL_NS}.${DOMAIN_SUFFIX}"
curl -sk "${VERIFY_ROUTE}/q/metrics" 2>/dev/null \
    | grep -E "^certificate_(verified|not_found)" \
    | head -10 || echo "  (verify-api not ready)"
pause

# ---- Step 6: Generate Metrics Activity ----
header "Step 6: Generate Metrics Activity"
echo -e "${GREEN}Issuing a certificate to generate metrics...${NC}"
echo ""

# Use the seed script or direct API call
CERT_ID="demo-mon-$(date +%s)"
PAYLOAD="{\"certID\":\"${CERT_ID}\",\"studentID\":\"student-demo\",\"studentName\":\"Demo Student\",\"courseID\":\"DEMO-101\",\"courseName\":\"Monitoring Demo Course\",\"orgID\":\"TechPulseMSP\",\"orgName\":\"TechPulse Academy\",\"issueDate\":\"2026-01-01\",\"expiryDate\":\"2027-01-01\"}"

# Get a token from Keycloak for cert-admin-api
KC_ROUTE="https://keycloak-certchain-techpulse.${DOMAIN_SUFFIX}"
TOKEN=$(curl -sk "${KC_ROUTE}/realms/techpulse/protocol/openid-connect/token" \
    -d "grant_type=password&client_id=course-manager-ui&username=admin@techpulse.demo&password=admin" \
    2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null) || true

if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
    echo "  Issuing certificate: $CERT_ID"
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
        -X POST "${ADMIN_ROUTE}/api/certificates" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>/dev/null) || HTTP_CODE="error"
    echo "  Issue response: HTTP $HTTP_CODE"

    echo "  Verifying certificate..."
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
        "${VERIFY_ROUTE}/api/verify/${CERT_ID}" 2>/dev/null) || HTTP_CODE="error"
    echo "  Verify response: HTTP $HTTP_CODE"
else
    echo "  [SKIP] Could not obtain Keycloak token (Keycloak may not be ready)"
    echo "  Run scripts/seed-demo-certificates.sh first to populate data"
fi
pause

# ---- Step 7: Grafana Dashboards ----
header "Step 7: Grafana Dashboards"

GRAFANA_ROUTE=$(oc get route -n "$CENTRAL_NS" -l app.kubernetes.io/name=grafana \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")

if [ -n "$GRAFANA_ROUTE" ]; then
    echo -e "${GREEN}Grafana is running!${NC}"
    echo ""
    echo "  URL:      https://${GRAFANA_ROUTE}"
    echo "  Login:    admin / certchain"
    echo ""
    echo "  Dashboards:"
    echo -e "    ${BLUE}• CertChain — Fabric Network${NC}    (peer proposals, block commits, orderer consensus)"
    echo -e "    ${BLUE}• CertChain — Application APIs${NC}  (certificate counters, HTTP rates, JVM metrics)"
    echo -e "    ${BLUE}• CertChain — Infrastructure${NC}    (CPU, memory, PVC usage, pod restarts)"
else
    echo "  Grafana route not found. It may still be deploying."
    echo "  Check: oc get pods -n $CENTRAL_NS -l app.kubernetes.io/name=grafana"
fi

echo ""
echo -e "${BOLD}Also available in OpenShift Console:${NC}"
echo "  Observe > Metrics — PromQL queries against all CertChain metrics"
echo "  Observe > Targets — ServiceMonitor scrape targets and health"

echo ""
header "Walkthrough Complete"
echo "The CertChain monitoring stack provides end-to-end observability:"
echo "  Fabric Layer:   Peer endorsements, block commits, orderer consensus"
echo "  Application:    Certificate ops counters, HTTP rates, JVM health"
echo "  Infrastructure: CPU, memory, PVC usage, pod restarts, network I/O"
echo ""
echo "All metrics flow: Apps -> ServiceMonitors -> Prometheus -> Grafana"
