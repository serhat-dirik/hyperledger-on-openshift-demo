#!/usr/bin/env bash
# generate-genesis.sh — Generates Fabric genesis block inside a Job pod.
# Extracts crypto from K8s secrets, builds MSP directories, runs configtxgen.
set -euo pipefail
echo "TIMING_START $(date +%s)"

CENTRAL_NS="${CENTRAL_NS:-certchain}"
CHANNEL_NAME="${CHANNEL_NAME:-certchannel}"
FABRIC_VERSION="${FABRIC_VERSION:-3.1.0}"

echo "=============================================="
echo " Genesis Block Generation"
echo "=============================================="
echo "  Channel: $CHANNEL_NAME"
echo ""

# Download configtxgen
if ! command -v configtxgen &>/dev/null; then
    echo "Downloading Fabric $FABRIC_VERSION binaries..."
    mkdir -p /tmp/bin
    curl -sL "https://github.com/hyperledger/fabric/releases/download/v${FABRIC_VERSION}/hyperledger-fabric-linux-amd64-${FABRIC_VERSION}.tar.gz" -o /tmp/fabric.tar.gz
    tar xzf /tmp/fabric.tar.gz -C /tmp
    rm -f /tmp/fabric.tar.gz
    export PATH="/tmp/bin:$PATH"
fi

# Install kubectl if not present
if ! command -v kubectl &>/dev/null; then
    echo "Downloading kubectl..."
    mkdir -p /tmp/bin
    curl -sL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /tmp/bin/kubectl
    chmod +x /tmp/bin/kubectl
fi

WORK_DIR="/work"
mkdir -p "$WORK_DIR"

# ── Idempotency check ──────────────────────────────────────────
# If genesis block ConfigMap already exists, skip regeneration.
if kubectl get configmap fabric-genesis -n "$CENTRAL_NS" &>/dev/null; then
    echo "[SKIP] Genesis block already exists. Delete ConfigMap 'fabric-genesis' to force re-run."
    echo "TIMING_END $(date +%s)"
    exit 0
fi
# ───────────────────────────────────────────────────────────────

# Extract CA cert (all orgs share same CA)
echo "[1/3] Extracting crypto from K8s secrets..."
CA_CERT=$(kubectl get secret orderer0-msp -n "$CENTRAL_NS" -o jsonpath='{.data.cacerts}' | base64 -d)

# Build MSP directories for each org
for ORG_ENTRY in "OrdererOrg:orderer:orderer0:orderer0-msp:orderer0-tls" \
                 "TechPulseMSP:techpulse:orderer1:orderer1-techpulse-msp:orderer1-techpulse-tls" \
                 "DataForgeMSP:dataforge:orderer2:orderer2-dataforge-msp:orderer2-dataforge-tls" \
                 "NeuralPathMSP:neuralpath:orderer3:orderer3-neuralpath-msp:orderer3-neuralpath-tls"; do
    IFS=: read -r MSP_ID ORG ORDERER_NAME MSP_SECRET TLS_SECRET <<< "$ORG_ENTRY"
    MSP_DIR="$WORK_DIR/msp/$ORG"
    mkdir -p "$MSP_DIR/cacerts" "$MSP_DIR/tlscacerts"
    echo "$CA_CERT" > "$MSP_DIR/cacerts/ca-cert.pem"
    echo "$CA_CERT" > "$MSP_DIR/tlscacerts/tlsca-cert.pem"
    cp /configtx/config.yaml "$MSP_DIR/config.yaml"

    # Orderer identity cert for BFT consenter mapping
    ORDERER_MSP_DIR="$MSP_DIR/orderers/$ORDERER_NAME/msp/signcerts"
    mkdir -p "$ORDERER_MSP_DIR"
    kubectl get secret "$MSP_SECRET" -n "$CENTRAL_NS" -o jsonpath='{.data.signcerts}' | base64 -d > "$ORDERER_MSP_DIR/cert.pem"

    # Orderer TLS cert
    TLS_DIR="$WORK_DIR/tls/$ORDERER_NAME"
    mkdir -p "$TLS_DIR"
    kubectl get secret "$TLS_SECRET" -n "$CENTRAL_NS" -o jsonpath='{.data.server\.crt}' | base64 -d > "$TLS_DIR/server.crt"
    echo "  [OK] MSP for $ORG ($MSP_ID)"
done

# --- Generate genesis block ---
echo "[2/3] Running configtxgen..."
cp /configtx/configtx.yaml "$WORK_DIR/configtx.yaml"
export FABRIC_CFG_PATH="$WORK_DIR"

configtxgen -profile CertChannelGenesis \
    -outputBlock "$WORK_DIR/genesis.block" \
    -channelID "$CHANNEL_NAME"

echo "  Genesis block generated ($(wc -c < "$WORK_DIR/genesis.block") bytes)"

# --- Save as ConfigMap ---
echo "[3/3] Saving genesis block to ConfigMap..."
kubectl create configmap fabric-genesis \
    --from-file=genesis.block="$WORK_DIR/genesis.block" \
    -n "$CENTRAL_NS" --dry-run=client -o yaml | kubectl apply -f -

echo "  [OK] Genesis block saved to ConfigMap fabric-genesis"
echo ""
echo "Genesis generation complete."
echo "TIMING_END $(date +%s)"
