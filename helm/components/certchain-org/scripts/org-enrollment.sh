#!/usr/bin/env bash
# org-enrollment.sh — Enrolls peer, orderer, and admin identities for an org.
# Runs inside a Job pod. Calls the Fabric CA directly over HTTP.
set -uo pipefail
echo "TIMING_START $(date +%s)"

export FABRIC_CA_CLIENT_HOME=/tmp/fabric-ca-client
mkdir -p "$FABRIC_CA_CLIENT_HOME"

ORG_NAME="${ORG_NAME:?ORG_NAME is required}"
ORG_NS="${ORG_NS:?ORG_NS is required}"
CENTRAL_NS="${CENTRAL_NS:-certchain}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-}"
CA_URL="${CA_URL:-http://fabric-ca.${CENTRAL_NS}.svc.cluster.local:7054}"
FABRIC_CA_VERSION="${FABRIC_CA_VERSION:-1.5.15}"

# Org-specific config
case "$ORG_NAME" in
    techpulse)  ORDERER_NAME="orderer1" ;;
    dataforge)  ORDERER_NAME="orderer2" ;;
    neuralpath) ORDERER_NAME="orderer3" ;;
    *) echo "ERROR: Unknown org '$ORG_NAME'"; exit 1 ;;
esac

PEER_NAME="peer0-${ORG_NAME}"

echo "=============================================="
echo " Org Enrollment: $ORG_NAME"
echo "=============================================="
echo "  Namespace:  $ORG_NS"
echo "  Orderer:    $ORDERER_NAME"
echo "  CA URL:     $CA_URL"
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
if kubectl get secret peer0-msp -n "$ORG_NS" &>/dev/null; then
    echo "[SKIP] peer0-msp secret already exists — enrollment already done."
    echo "TIMING_END $(date +%s)"
    exit 0
fi

# Wait for CA to be ready
echo "[1/3] Waiting for Fabric CA..."
for i in $(seq 1 30); do
    if curl -sf "$CA_URL/cainfo" &>/dev/null; then
        echo "  CA is ready"
        break
    fi
    echo "  Waiting for CA... ($i/30)"
    sleep 5
done

# Helper: enroll an identity (idempotent — resets password before enrollment)
enroll_identity() {
    local id_name="$1"
    local msp_dir="$2"
    local profile="${3:-}"
    local csr_hosts="${4:-}"

    # Reset password so enrollment works even on retry
    fabric-ca-client identity modify "$id_name" \
        --secret "${id_name}pw" \
        -u "$CA_URL" \
        -M "$WORK_DIR/ca-admin-msp" 2>/dev/null || true

    local enroll_args=(-u "http://${id_name}:${id_name}pw@${CA_URL#http://}" -M "$msp_dir")
    [ -n "$profile" ] && enroll_args+=(--enrollment.profile "$profile")
    [ -n "$csr_hosts" ] && enroll_args+=(--csr.hosts "$csr_hosts")

    fabric-ca-client enroll "${enroll_args[@]}" 2>&1
}

# --- Step 2: Enroll identities ---
echo "[2/3] Enrolling identities..."

# Enroll CA admin
fabric-ca-client enroll \
    -u "http://admin:adminpw@${CA_URL#http://}" \
    -M "$WORK_DIR/ca-admin-msp" 2>&1 || {
    echo "  [ERROR] CA admin enrollment failed. Is the CA running?"
    exit 1
}

# Peer MSP + TLS
PEER_CSR="peer0,peer0.${ORG_NS}.svc.cluster.local,peer0-${ORG_NS}.${DOMAIN_SUFFIX}"
echo "  Enrolling $PEER_NAME MSP..."
enroll_identity "$PEER_NAME" "$WORK_DIR/${PEER_NAME}-msp"
echo "  Enrolling $PEER_NAME TLS..."
enroll_identity "$PEER_NAME" "$WORK_DIR/${PEER_NAME}-tls" tls "$PEER_CSR"

# Orderer MSP + TLS
ORD_ID="${ORDERER_NAME}-${ORG_NAME}"
ORD_CSR="orderer,orderer.${ORG_NS}.svc.cluster.local,${ORDERER_NAME}-${ORG_NS}.${DOMAIN_SUFFIX}"
echo "  Enrolling $ORD_ID MSP..."
enroll_identity "$ORD_ID" "$WORK_DIR/${ORD_ID}-msp"
echo "  Enrolling $ORD_ID TLS..."
enroll_identity "$ORD_ID" "$WORK_DIR/${ORD_ID}-tls" tls "$ORD_CSR"

# Admin MSP
ADMIN_ID="admin-${ORG_NAME}"
echo "  Enrolling $ADMIN_ID..."
enroll_identity "$ADMIN_ID" "$WORK_DIR/${ADMIN_ID}-msp"

# --- Step 3: Create K8s secrets ---
echo "[3/3] Creating K8s secrets..."

# Helper: create MSP secret
create_msp_secret() {
    local secret_name=$1
    local msp_dir=$2
    local namespace=$3

    local signcert=$(find "$msp_dir/signcerts" -name '*.pem' 2>/dev/null | head -1)
    local keystore=$(find "$msp_dir/keystore" -name '*_sk' 2>/dev/null | head -1)
    local cacert=$(find "$msp_dir/cacerts" -name '*.pem' 2>/dev/null | head -1)
    local tlscacert=$(find "$msp_dir/tlscacerts" -name '*.pem' 2>/dev/null | head -1)
    [ -z "$tlscacert" ] && tlscacert="$cacert"

    if [ -z "$signcert" ] || [ -z "$keystore" ] || [ -z "$cacert" ]; then
        echo "  [ERROR] Missing crypto for $secret_name"
        exit 1
    fi

    kubectl create secret generic "$secret_name" \
        --from-file=signcerts="$signcert" \
        --from-file=keystore="$keystore" \
        --from-file=cacerts="$cacert" \
        --from-file=tlscacerts="$tlscacert" \
        --from-file=config.yaml=/msp-config/config.yaml \
        -n "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    echo "  [OK] Secret: $secret_name"
}

# Helper: create TLS secret
create_tls_secret() {
    local secret_name=$1
    local tls_dir=$2
    local namespace=$3

    local cert=$(find "$tls_dir/signcerts" -name '*.pem' 2>/dev/null | head -1)
    local key=$(find "$tls_dir/keystore" -name '*_sk' 2>/dev/null | head -1)
    local ca=$(find "$tls_dir/tlscacerts" -name '*.pem' 2>/dev/null | head -1)
    [ -z "$ca" ] && ca=$(find "$tls_dir/cacerts" -name '*.pem' 2>/dev/null | head -1)

    if [ -z "$cert" ] || [ -z "$key" ]; then
        echo "  [ERROR] Missing TLS crypto for $secret_name"
        exit 1
    fi

    kubectl create secret generic "$secret_name" \
        --from-file=server.crt="$cert" \
        --from-file=server.key="$key" \
        --from-file=ca.crt="$ca" \
        -n "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    echo "  [OK] Secret: $secret_name"
}

# Peer secrets (generic names in org NS)
create_msp_secret "peer0-msp" "$WORK_DIR/${PEER_NAME}-msp" "$ORG_NS"
create_tls_secret "peer0-tls" "$WORK_DIR/${PEER_NAME}-tls" "$ORG_NS"

# Orderer secrets (generic names in org NS)
create_msp_secret "orderer-msp" "$WORK_DIR/${ORD_ID}-msp" "$ORG_NS"
create_tls_secret "orderer-tls" "$WORK_DIR/${ORD_ID}-tls" "$ORG_NS"

# Admin secret
create_msp_secret "admin-msp" "$WORK_DIR/${ADMIN_ID}-msp" "$ORG_NS"

rm -rf "$WORK_DIR"
echo ""
echo "Org enrollment complete: $ORG_NAME"
echo "TIMING_END $(date +%s)"
