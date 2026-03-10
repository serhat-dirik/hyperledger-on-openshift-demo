#!/usr/bin/env bash
# seed-demo-certificates.sh — Loads demo data into the running CertChain deployment.
# Issues certificates via each org's cert-admin-api.
# Student users are pre-seeded in org KC realm JSONs (no manual creation needed).
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
KC_TECHPULSE="https://keycloak-certchain-techpulse.${DOMAIN_SUFFIX}"
KC_DATAFORGE="https://keycloak-certchain-dataforge.${DOMAIN_SUFFIX}"
KC_NEURALPATH="https://keycloak-certchain-neuralpath.${DOMAIN_SUFFIX}"

API_TECHPULSE="https://cert-admin-api-certchain-techpulse.${DOMAIN_SUFFIX}"
API_DATAFORGE="https://cert-admin-api-certchain-dataforge.${DOMAIN_SUFFIX}"
API_NEURALPATH="https://cert-admin-api-certchain-neuralpath.${DOMAIN_SUFFIX}"

VERIFY_API="https://verify-api-certchain.${DOMAIN_SUFFIX}"

echo "=== Seeding CertChain Demo Data ==="
echo "  TechPulse API:    $API_TECHPULSE"
echo "  DataForge API:    $API_DATAFORGE"
echo "  NeuralPath API:   $API_NEURALPATH"
echo ""

# --- Helper: get admin token from org KC ---
get_org_token() {
    local kc_url="$1" realm="$2" username="$3"
    curl -sS -k "$kc_url/realms/$realm/protocol/openid-connect/token" \
        -d "client_id=course-manager-ui" \
        -d "username=$username" \
        -d "password=admin" \
        -d "grant_type=password" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
}

# --- Helper: issue certificate ---
issue_cert() {
    local api_url=$1 token=$2 certid=$3 studentid=$4 studentname=$5
    local courseid=$6 coursename=$7 issuedate=$8 expirydate=$9
    local grade=${10:-} degree=${11:-}

    local json="{
        \"certID\": \"$certid\",
        \"studentID\": \"$studentid\",
        \"studentName\": \"$studentname\",
        \"courseID\": \"$courseid\",
        \"courseName\": \"$coursename\",
        \"issueDate\": \"$issuedate\",
        \"expiryDate\": \"$expirydate\""
    [ -n "$grade" ]  && json="$json, \"grade\": \"$grade\""
    [ -n "$degree" ] && json="$json, \"degree\": \"$degree\""
    json="$json}"

    HTTP=$(curl -sS -k -X POST "$api_url/api/v1/certificates" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$json" -o /dev/null -w "%{http_code}")
    echo "$HTTP"
}

# --- Step 1: Issue TechPulse certificates ---
echo "[1/4] Issuing TechPulse Academy certificates..."
ISSUE_DATE=$(date +%Y-%m-%d)
EXPIRY_DATE=$(date -v+2y +%Y-%m-%d 2>/dev/null || date -d "+2 years" +%Y-%m-%d 2>/dev/null || echo "2028-03-04")

TP_TOKEN=$(get_org_token "$KC_TECHPULSE" "techpulse" "admin@techpulse.demo" 2>/dev/null || echo "")
if [ -n "$TP_TOKEN" ]; then
    issue_cert "$API_TECHPULSE" "$TP_TOKEN" "TP-FSWD-001" "student01" "Alice Chen" "FSWD-101" "Full-Stack Web Dev" "$ISSUE_DATE" "$EXPIRY_DATE" "A" "Professional Certificate"
    issue_cert "$API_TECHPULSE" "$TP_TOKEN" "TP-FSWD-002" "student02" "Bob Martinez" "FSWD-101" "Full-Stack Web Dev" "$ISSUE_DATE" "$EXPIRY_DATE" "B+" "Professional Certificate"
    issue_cert "$API_TECHPULSE" "$TP_TOKEN" "TP-CNM-001" "student01" "Alice Chen" "CNM-201" "Cloud-Native Microservices" "$ISSUE_DATE" "$EXPIRY_DATE" "A+" "Advanced Certificate"
    issue_cert "$API_TECHPULSE" "$TP_TOKEN" "TP-DSO-001" "student02" "Bob Martinez" "DSO-301" "DevSecOps Fundamentals" "$ISSUE_DATE" "$EXPIRY_DATE" "A-" "Professional Certificate"
    issue_cert "$API_TECHPULSE" "$TP_TOKEN" "TP-CNM-002" "student01" "Alice Chen" "CNM-201" "Cloud-Native Microservices" "$ISSUE_DATE" "$EXPIRY_DATE" "A" "Advanced Certificate"
    echo "    5 certs issued for TechPulse."
else
    echo "    WARNING: Could not get TechPulse admin token from $KC_TECHPULSE"
fi

# --- Step 2: Issue DataForge certificates ---
echo "[2/4] Issuing DataForge Institute certificates..."
DF_TOKEN=$(get_org_token "$KC_DATAFORGE" "dataforge" "admin@dataforge.demo" 2>/dev/null || echo "")
if [ -n "$DF_TOKEN" ]; then
    issue_cert "$API_DATAFORGE" "$DF_TOKEN" "DF-PGA-001" "student03" "Carol Wang" "PGA-101" "PostgreSQL Administration" "$ISSUE_DATE" "$EXPIRY_DATE" "A" "Associate Certificate"
    issue_cert "$API_DATAFORGE" "$DF_TOKEN" "DF-DPE-001" "student04" "David Kim" "DPE-201" "Data Pipeline Engineering" "$ISSUE_DATE" "$EXPIRY_DATE" "B" "Professional Certificate"
    issue_cert "$API_DATAFORGE" "$DF_TOKEN" "DF-PGA-002" "student03" "Carol Wang" "PGA-101" "PostgreSQL Administration" "$ISSUE_DATE" "$EXPIRY_DATE" "A-" "Associate Certificate"
    issue_cert "$API_DATAFORGE" "$DF_TOKEN" "DF-GDB-001" "student04" "David Kim" "GDB-301" "Graph Databases Masterclass" "$ISSUE_DATE" "$EXPIRY_DATE" "A+" "Advanced Certificate"
    issue_cert "$API_DATAFORGE" "$DF_TOKEN" "DF-DPE-002" "student03" "Carol Wang" "DPE-201" "Data Pipeline Engineering" "$ISSUE_DATE" "$EXPIRY_DATE" "B+" "Professional Certificate"
    echo "    5 certs issued for DataForge."
else
    echo "    WARNING: Could not get DataForge admin token from $KC_DATAFORGE"
fi

# --- Step 3: Issue NeuralPath certificates ---
echo "[3/4] Issuing NeuralPath Labs certificates..."
NP_TOKEN=$(get_org_token "$KC_NEURALPATH" "neuralpath" "admin@neuralpath.demo" 2>/dev/null || echo "")
if [ -n "$NP_TOKEN" ]; then
    issue_cert "$API_NEURALPATH" "$NP_TOKEN" "NP-AML-001" "student05" "Eva Patel" "AML-101" "Applied Machine Learning" "$ISSUE_DATE" "$EXPIRY_DATE" "A" "Master Certificate"
    issue_cert "$API_NEURALPATH" "$NP_TOKEN" "NP-LFT-001" "student06" "Frank Liu" "LFT-201" "LLM Fine-Tuning Workshop" "$ISSUE_DATE" "$EXPIRY_DATE" "A+" "Advanced Certificate"
    issue_cert "$API_NEURALPATH" "$NP_TOKEN" "NP-CVP-001" "student05" "Eva Patel" "CVP-301" "Computer Vision Practicum" "$ISSUE_DATE" "$EXPIRY_DATE" "B+" "Master Certificate"
    issue_cert "$API_NEURALPATH" "$NP_TOKEN" "NP-AML-002" "student06" "Frank Liu" "AML-101" "Applied Machine Learning" "$ISSUE_DATE" "$EXPIRY_DATE" "A-" "Master Certificate"
    issue_cert "$API_NEURALPATH" "$NP_TOKEN" "NP-LFT-002" "student05" "Eva Patel" "LFT-201" "LLM Fine-Tuning Workshop" "$ISSUE_DATE" "$EXPIRY_DATE" "A" "Advanced Certificate"
    echo "    5 certs issued for NeuralPath."
else
    echo "    WARNING: Could not get NeuralPath admin token from $KC_NEURALPATH"
fi

# --- Step 4: Verify seed data ---
echo "[4/4] Verifying seed data..."
for certid in "TP-FSWD-001" "DF-PGA-001" "NP-AML-001"; do
    STATUS=$(curl -sS -k "$VERIFY_API/api/v1/verify/$certid" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "UNAVAILABLE")
    echo "  $certid: $STATUS"
done

echo ""
echo "=== Seed complete ==="
echo "Admin users (org KC, password: admin):"
echo "  TechPulse:   admin@techpulse.demo  @ $KC_TECHPULSE"
echo "  DataForge:   admin@dataforge.demo  @ $KC_DATAFORGE"
echo "  NeuralPath:  admin@neuralpath.demo  @ $KC_NEURALPATH"
echo ""
echo "Student users (org KC, password: student — login via cert-portal identity brokering):"
echo "  student01@techpulse.demo, student02@techpulse.demo"
echo "  student03@dataforge.demo, student04@dataforge.demo"
echo "  student05@neuralpath.demo, student06@neuralpath.demo"
