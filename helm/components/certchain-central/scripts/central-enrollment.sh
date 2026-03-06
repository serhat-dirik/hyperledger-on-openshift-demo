#!/usr/bin/env bash
# central-enrollment.sh — Enrolls orderer0 identity and registers org identities.
# Runs inside a Job pod with fabric-ca-client binary.
# Calls the Fabric CA directly over HTTP (no oc exec).
set -uo pipefail
echo "TIMING_START $(date +%s)"

export FABRIC_CA_CLIENT_HOME=/tmp/fabric-ca-client
mkdir -p "$FABRIC_CA_CLIENT_HOME"

CENTRAL_NS="${CENTRAL_NS:-certchain}"
CA_URL="${CA_URL:-http://fabric-ca:7054}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-}"
FABRIC_CA_VERSION="${FABRIC_CA_VERSION:-1.5.15}"

echo "=============================================="
echo " Central Enrollment"
echo "=============================================="
echo "  CA URL:    $CA_URL"
echo "  Namespace: $CENTRAL_NS"
echo ""

# Download fabric-ca-client if not on PATH
if ! command -v fabric-ca-client &>/dev/null; then
    echo "Downloading fabric-ca-client v${FABRIC_CA_VERSION}..."
    mkdir -p /tmp/bin
    curl -sL "https://github.com/hyperledger/fabric-ca/releases/download/v${FABRIC_CA_VERSION}/hyperledger-fabric-ca-linux-amd64-${FABRIC_CA_VERSION}.tar.gz" -o /tmp/fabric-ca.tar.gz
    tar xzf /tmp/fabric-ca.tar.gz -C /tmp
    rm -f /tmp/fabric-ca.tar.gz
    export PATH="/tmp/bin:$PATH"
fi

# Install kubectl if not present
if ! command -v kubectl &>/dev/null; then
    echo "Downloading kubectl..."
    mkdir -p /tmp/bin
    curl -sL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /tmp/bin/kubectl
    chmod +x /tmp/bin/kubectl
fi

WORK_DIR=$(mktemp -d)

# Skip if already completed (idempotency)
if kubectl get secret orderer0-msp -n "$CENTRAL_NS" &>/dev/null; then
    echo "[SKIP] orderer0-msp secret already exists — enrollment already done."
    echo "TIMING_END $(date +%s)"
    exit 0
fi

# Helper: register + enroll an identity (idempotent)
enroll_identity() {
    local id_name="$1"
    local id_type="$2"
    local msp_dir="$3"
    local profile="${4:-}"
    local csr_hosts="${5:-}"

    # Register (ignore if already registered)
    fabric-ca-client register \
        --id.name "$id_name" \
        --id.secret "${id_name}pw" \
        --id.type "$id_type" \
        -u "$CA_URL" \
        -M "$WORK_DIR/ca-admin-msp" 2>/dev/null || true

    # Reset password so enrollment always works (even on retry)
    fabric-ca-client identity modify "$id_name" \
        --secret "${id_name}pw" \
        -u "$CA_URL" \
        -M "$WORK_DIR/ca-admin-msp" 2>/dev/null || true

    # Build enroll command
    local enroll_args=(-u "http://${id_name}:${id_name}pw@${CA_URL#http://}" -M "$msp_dir")
    [ -n "$profile" ] && enroll_args+=(--enrollment.profile "$profile")
    [ -n "$csr_hosts" ] && enroll_args+=(--csr.hosts "$csr_hosts")

    fabric-ca-client enroll "${enroll_args[@]}" 2>&1
}

# --- Step 1: Enroll CA admin ---
echo "[1/4] Enrolling CA admin..."
fabric-ca-client enroll \
    -u "http://admin:adminpw@${CA_URL#http://}" \
    -M "$WORK_DIR/ca-admin-msp" 2>&1 || {
    echo "  [ERROR] CA admin enrollment failed. Is the CA running?"
    exit 1
}

# --- Step 2: Register and enroll orderer0 ---
echo "[2/4] Registering and enrolling orderer0..."

echo "  Enrolling orderer0 MSP..."
enroll_identity orderer0 orderer "$WORK_DIR/orderer0-msp"

echo "  Enrolling orderer0 TLS..."
ORDERER0_CSR="orderer0,orderer0.${CENTRAL_NS}.svc.cluster.local,orderer0-${CENTRAL_NS}.${DOMAIN_SUFFIX}"
enroll_identity orderer0 orderer "$WORK_DIR/orderer0-tls" tls "$ORDERER0_CSR"

# --- Step 3: Create K8s secrets for orderer0 ---
echo "[3/4] Creating orderer0 K8s secrets..."

# MSP secret
SIGNCERT=$(find "$WORK_DIR/orderer0-msp/signcerts" -name '*.pem' | head -1)
KEYSTORE=$(find "$WORK_DIR/orderer0-msp/keystore" -name '*_sk' | head -1)
CACERT=$(find "$WORK_DIR/orderer0-msp/cacerts" -name '*.pem' | head -1)
TLSCACERT=$(find "$WORK_DIR/orderer0-msp/tlscacerts" -name '*.pem' 2>/dev/null | head -1)
[ -z "$TLSCACERT" ] && TLSCACERT="$CACERT"

if [ -z "$SIGNCERT" ] || [ -z "$KEYSTORE" ] || [ -z "$CACERT" ]; then
    echo "  [ERROR] MSP enrollment produced incomplete output"
    ls -laR "$WORK_DIR/orderer0-msp/" 2>&1
    exit 1
fi

kubectl create secret generic orderer0-msp \
    --from-file=signcerts="$SIGNCERT" \
    --from-file=keystore="$KEYSTORE" \
    --from-file=cacerts="$CACERT" \
    --from-file=tlscacerts="$TLSCACERT" \
    --from-file=config.yaml=/msp-config/config.yaml \
    -n "$CENTRAL_NS" --dry-run=client -o yaml | kubectl apply -f -

# TLS secret
TLS_CERT=$(find "$WORK_DIR/orderer0-tls/signcerts" -name '*.pem' | head -1)
TLS_KEY=$(find "$WORK_DIR/orderer0-tls/keystore" -name '*_sk' | head -1)
TLS_CA=$(find "$WORK_DIR/orderer0-tls/tlscacerts" -name '*.pem' 2>/dev/null | head -1)
[ -z "$TLS_CA" ] && TLS_CA=$(find "$WORK_DIR/orderer0-tls/cacerts" -name '*.pem' | head -1)

kubectl create secret generic orderer0-tls \
    --from-file=server.crt="$TLS_CERT" \
    --from-file=server.key="$TLS_KEY" \
    --from-file=ca.crt="$TLS_CA" \
    -n "$CENTRAL_NS" --dry-run=client -o yaml | kubectl apply -f -
echo "  [OK] orderer0 secrets created"

# --- Step 4: Register org identities ---
echo "[4/4] Registering org identities..."

IDENTITY_NAMES=(
    peer0-techpulse peer0-dataforge peer0-neuralpath
    orderer1-techpulse orderer2-dataforge orderer3-neuralpath
    admin-techpulse admin-dataforge admin-neuralpath
)
IDENTITY_TYPES=(
    peer peer peer
    orderer orderer orderer
    admin admin admin
)

for i in $(seq 0 $((${#IDENTITY_NAMES[@]} - 1))); do
    identity="${IDENTITY_NAMES[$i]}"
    id_type="${IDENTITY_TYPES[$i]}"
    echo "  Registering $identity (type: $id_type)..."
    fabric-ca-client register \
        --id.name "$identity" \
        --id.secret "${identity}pw" \
        --id.type "$id_type" \
        -u "$CA_URL" \
        -M "$WORK_DIR/ca-admin-msp" 2>/dev/null || echo "  ($identity may already be registered)"
done
echo "  [OK] All org identities registered"

rm -rf "$WORK_DIR"
echo ""
echo "Central enrollment complete."
echo "TIMING_END $(date +%s)"
