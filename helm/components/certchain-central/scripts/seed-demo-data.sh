#!/usr/bin/env bash
# seed-demo-data.sh — Run inside a Job pod (wave 13)
# Seeds demo certificates via each org's cert-admin-api.
set -euo pipefail

DOMAIN="$1"

ORGS=("techpulse" "dataforge" "neuralpath")
ISSUE_DATE=$(date +%Y-%m-%d)
EXPIRY_DATE=$(date -d "+2 years" +%Y-%m-%d 2>/dev/null || echo "2028-03-16")

get_token() {
  local org=$1
  local KC="https://keycloak-certchain-${org}.${DOMAIN}"
  for attempt in $(seq 1 30); do
    TOKEN=$(curl -sk -X POST "${KC}/realms/${org}/protocol/openid-connect/token" \
      -d "client_id=course-manager-ui" -d "username=admin@${org}.demo" \
      -d "password=admin" -d "grant_type=password" 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    if [ -n "$TOKEN" ]; then echo "$TOKEN"; return 0; fi
    echo "  Waiting for ${org} KC/API... (attempt $attempt/30)" >&2
    sleep 10
  done
  echo "" ; return 1
}

issue() {
  local api=$1 token=$2 id=$3 student=$4 name=$5 cid=$6 cname=$7 grade=$8 degree=$9
  local json="{\"certID\":\"${id}\",\"studentID\":\"${student}\",\"studentName\":\"${name}\",\"courseID\":\"${cid}\",\"courseName\":\"${cname}\",\"issueDate\":\"${ISSUE_DATE}\",\"expiryDate\":\"${EXPIRY_DATE}\",\"grade\":\"${grade}\",\"degree\":\"${degree}\"}"
  HTTP=$(curl -sk -X POST "${api}/api/v1/certificates" \
    -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
    -d "$json" -o /dev/null -w "%{http_code}")
  echo "  ${id}: HTTP ${HTTP}"
}

echo "=== Seeding CertChain Demo Data ==="

# --- TechPulse ---
echo "[1/3] TechPulse Academy..."
TP_API="https://cert-admin-api-certchain-techpulse.${DOMAIN}"
TP_TOKEN=$(get_token "techpulse")
if [ -n "$TP_TOKEN" ]; then
  issue "$TP_API" "$TP_TOKEN" "TP-FSWD-001" "student01@techpulse.demo" "Alice Chen"    "FSWD-101" "Full-Stack Web Dev"        "A"  "Professional Certificate"
  issue "$TP_API" "$TP_TOKEN" "TP-FSWD-002" "student02@techpulse.demo" "Bob Martinez"  "FSWD-101" "Full-Stack Web Dev"        "B+" "Professional Certificate"
  issue "$TP_API" "$TP_TOKEN" "TP-CNM-001"  "student01@techpulse.demo" "Alice Chen"    "CNM-201"  "Cloud-Native Microservices" "A+" "Advanced Certificate"
  issue "$TP_API" "$TP_TOKEN" "TP-DSO-001"  "student02@techpulse.demo" "Bob Martinez"  "DSO-301"  "DevSecOps Fundamentals"     "A-" "Professional Certificate"
  issue "$TP_API" "$TP_TOKEN" "TP-CNM-002"  "student01@techpulse.demo" "Alice Chen"    "CNM-201"  "Cloud-Native Microservices" "A"  "Advanced Certificate"
else
  echo "  WARNING: Could not get TechPulse token"
fi

# --- DataForge ---
echo "[2/3] DataForge Institute..."
DF_API="https://cert-admin-api-certchain-dataforge.${DOMAIN}"
DF_TOKEN=$(get_token "dataforge")
if [ -n "$DF_TOKEN" ]; then
  issue "$DF_API" "$DF_TOKEN" "DF-PGA-001"  "student03@dataforge.demo" "Carol Wang" "PGA-101" "PostgreSQL Administration"   "A"  "Associate Certificate"
  issue "$DF_API" "$DF_TOKEN" "DF-DPE-001"  "student04@dataforge.demo" "David Kim"  "DPE-201" "Data Pipeline Engineering"   "B"  "Professional Certificate"
  issue "$DF_API" "$DF_TOKEN" "DF-PGA-002"  "student03@dataforge.demo" "Carol Wang" "PGA-101" "PostgreSQL Administration"   "A-" "Associate Certificate"
  issue "$DF_API" "$DF_TOKEN" "DF-GDB-001"  "student04@dataforge.demo" "David Kim"  "GDB-301" "Graph Databases Masterclass" "A+" "Advanced Certificate"
  issue "$DF_API" "$DF_TOKEN" "DF-DPE-002"  "student03@dataforge.demo" "Carol Wang" "DPE-201" "Data Pipeline Engineering"   "B+" "Professional Certificate"
else
  echo "  WARNING: Could not get DataForge token"
fi

# --- NeuralPath ---
echo "[3/3] NeuralPath Labs..."
NP_API="https://cert-admin-api-certchain-neuralpath.${DOMAIN}"
NP_TOKEN=$(get_token "neuralpath")
if [ -n "$NP_TOKEN" ]; then
  issue "$NP_API" "$NP_TOKEN" "NP-AML-001"  "student05@neuralpath.demo" "Eva Patel"  "AML-101" "Applied Machine Learning"    "A"  "Master Certificate"
  issue "$NP_API" "$NP_TOKEN" "NP-LFT-001"  "student06@neuralpath.demo" "Frank Liu"  "LFT-201" "LLM Fine-Tuning Workshop"    "A+" "Advanced Certificate"
  issue "$NP_API" "$NP_TOKEN" "NP-CVP-001"  "student05@neuralpath.demo" "Eva Patel"  "CVP-301" "Computer Vision Practicum"    "B+" "Master Certificate"
  issue "$NP_API" "$NP_TOKEN" "NP-AML-002"  "student06@neuralpath.demo" "Frank Liu"  "AML-101" "Applied Machine Learning"     "A-" "Master Certificate"
  issue "$NP_API" "$NP_TOKEN" "NP-LFT-002"  "student05@neuralpath.demo" "Eva Patel"  "LFT-201" "LLM Fine-Tuning Workshop"     "A"  "Advanced Certificate"
else
  echo "  WARNING: Could not get NeuralPath token"
fi

# --- Verify ---
echo "==> Verifying..."
VERIFY="https://verify-api-certchain.${DOMAIN}"
for certid in "TP-FSWD-001" "DF-PGA-001" "NP-AML-001"; do
  STATUS=$(curl -sk "$VERIFY/api/v1/verify/$certid" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "UNAVAILABLE")
  echo "  $certid: $STATUS"
done

echo "=== Seed complete ==="
