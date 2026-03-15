#!/usr/bin/env bash
set -euo pipefail
cd /work

CC_NAME="certcontract"
CC_VERSION="1.0"
CC_SEQUENCE=${CC_SEQUENCE:-1}
CHANNEL_NAME="certchannel"
ORDERER_ENDPOINT="orderer0:7050"
# CcaaS: chaincode service runs in certchain namespace
CC_ADDRESS="certcontract:7052"

# Install kubectl
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
K="./kubectl"

# ── Idempotency check ──────────────────────────────────────────
# If chaincode-id ConfigMap already exists, chaincode is committed.
# Skip entire lifecycle to avoid package ID drift on re-sync.
EXISTING_PKGID=$($K get configmap chaincode-id -n certchain -o jsonpath='{.data.package-id}' 2>/dev/null || echo "")
if [ -n "$EXISTING_PKGID" ]; then
    echo "[SKIP] Chaincode already committed (package-id: $EXISTING_PKGID). Delete ConfigMap 'chaincode-id' to force re-run."
    exit 0
fi
# ───────────────────────────────────────────────────────────────

# Auto-detect current committed sequence and increment
# This handles re-runs after peer restarts when orderer retains state
AUTO_DETECT_SEQUENCE() {
  local DETECT_MSP_DIR="/work/detect-msp"
  mkdir -p $DETECT_MSP_DIR/signcerts $DETECT_MSP_DIR/keystore $DETECT_MSP_DIR/cacerts $DETECT_MSP_DIR/tlscacerts
  $K get secret admin-msp -n certchain-techpulse -o jsonpath='{.data.signcerts}' | base64 -d > $DETECT_MSP_DIR/signcerts/cert.pem 2>/dev/null || return 1
  $K get secret admin-msp -n certchain-techpulse -o jsonpath='{.data.keystore}' | base64 -d > $DETECT_MSP_DIR/keystore/key.pem 2>/dev/null || return 1
  $K get secret admin-msp -n certchain-techpulse -o jsonpath='{.data.cacerts}' | base64 -d > $DETECT_MSP_DIR/cacerts/ca.pem 2>/dev/null || return 1
  $K get secret admin-msp -n certchain-techpulse -o jsonpath='{.data.tlscacerts}' | base64 -d > $DETECT_MSP_DIR/tlscacerts/tlsca.pem 2>/dev/null || return 1
  $K get secret admin-msp -n certchain-techpulse -o jsonpath='{.data.config\.yaml}' | base64 -d > $DETECT_MSP_DIR/config.yaml 2>/dev/null || return 1
  local DETECT_TLS_DIR="/work/detect-tls"
  mkdir -p $DETECT_TLS_DIR
  $K get secret peer0-tls -n certchain-techpulse -o jsonpath='{.data.ca\.crt}' | base64 -d > $DETECT_TLS_DIR/ca.crt 2>/dev/null || return 1
  CORE_PEER_TLS_ENABLED=true CORE_PEER_LOCALMSPID=TechPulseMSP CORE_PEER_MSPCONFIGPATH=$DETECT_MSP_DIR CORE_PEER_ADDRESS=peer0.certchain-techpulse.svc.cluster.local:7051 CORE_PEER_TLS_ROOTCERT_FILE=$DETECT_TLS_DIR/ca.crt \
    peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name $CC_NAME 2>/dev/null | grep -oP 'Sequence: \K[0-9]+' || echo "0"
}

# Path setup
ORDERER_TLS_DIR="/work/orderer-tls"
mkdir -p $ORDERER_TLS_DIR
# Get orderer TLS CA cert from secret
$K get secret orderer0-tls -n certchain -o jsonpath='{.data.ca\.crt}' | base64 -d > $ORDERER_TLS_DIR/ca.crt
ORDERER_CA=$ORDERER_TLS_DIR/ca.crt
# FABRIC_CFG_PATH set by job (points to /tmp/config with core.yaml from tarball)
export CORE_PEER_TLS_ENABLED=true

# Auto-detect sequence if not explicitly set
if [ "$CC_SEQUENCE" = "1" ]; then
  CURRENT_SEQ=$(AUTO_DETECT_SEQUENCE || echo "0")
  if [ "$CURRENT_SEQ" -gt 0 ] 2>/dev/null; then
    CC_SEQUENCE=$((CURRENT_SEQ + 1))
    echo "Detected committed sequence $CURRENT_SEQ, using sequence $CC_SEQUENCE"
  fi
fi
echo "Using CC_SEQUENCE=$CC_SEQUENCE"

# =================================================================
# Step 1: Create CcaaS chaincode package (connection.json only)
# =================================================================
echo "============================================="
echo "  Step 1: Creating CcaaS chaincode package"
echo "============================================="
mkdir -p /work/cc-package/code /work/cc-package/pkg

cat > /work/cc-package/code/connection.json <<CONNEOF
{
  "address": "${CC_ADDRESS}",
  "dial_timeout": "10s",
  "tls_required": false
}
CONNEOF

cat > /work/cc-package/code/metadata.json <<METAEOF
{
  "type": "ccaas",
  "label": "${CC_NAME}_${CC_VERSION}"
}
METAEOF

# Package into tar.gz (Fabric lifecycle expects this format)
cd /work/cc-package/code
tar czf /work/cc-package/code.tar.gz connection.json metadata.json
cd /work/cc-package
cat > metadata.json <<OUTEREOF
{
  "type": "ccaas",
  "label": "${CC_NAME}_${CC_VERSION}"
}
OUTEREOF
tar czf /work/${CC_NAME}.tar.gz metadata.json code.tar.gz
cd /work
echo "Package created: ${CC_NAME}.tar.gz"

# =================================================================
# Step 2: Install chaincode on all peers
# =================================================================
echo ""
echo "============================================="
echo "  Step 2: Installing chaincode on peers"
echo "============================================="

PACKAGE_ID=""

for ORG in techpulse dataforge neuralpath; do
  case $ORG in
    techpulse)  MSP_ID="TechPulseMSP" ;;
    dataforge)  MSP_ID="DataForgeMSP" ;;
    neuralpath) MSP_ID="NeuralPathMSP" ;;
  esac

  echo "--- Installing on peer0-${ORG} ---"

  # Extract admin MSP from secrets
  ORG_NS="certchain-${ORG}"
  ADMIN_MSP_DIR="/work/admin-msp-${ORG}"
  mkdir -p $ADMIN_MSP_DIR/signcerts $ADMIN_MSP_DIR/keystore $ADMIN_MSP_DIR/cacerts $ADMIN_MSP_DIR/tlscacerts

  $K get secret admin-msp -n $ORG_NS -o jsonpath='{.data.signcerts}' | base64 -d > $ADMIN_MSP_DIR/signcerts/cert.pem
  $K get secret admin-msp -n $ORG_NS -o jsonpath='{.data.keystore}' | base64 -d > $ADMIN_MSP_DIR/keystore/key.pem
  $K get secret admin-msp -n $ORG_NS -o jsonpath='{.data.cacerts}' | base64 -d > $ADMIN_MSP_DIR/cacerts/ca.pem
  $K get secret admin-msp -n $ORG_NS -o jsonpath='{.data.tlscacerts}' | base64 -d > $ADMIN_MSP_DIR/tlscacerts/tlsca.pem
  $K get secret admin-msp -n $ORG_NS -o jsonpath='{.data.config\.yaml}' | base64 -d > $ADMIN_MSP_DIR/config.yaml

  # Get peer TLS CA for client connection
  PEER_TLS_DIR="/work/peer-tls-${ORG}"
  mkdir -p $PEER_TLS_DIR
  $K get secret peer0-tls -n $ORG_NS -o jsonpath='{.data.ca\.crt}' | base64 -d > $PEER_TLS_DIR/ca.crt

  export CORE_PEER_LOCALMSPID=$MSP_ID
  export CORE_PEER_MSPCONFIGPATH=$ADMIN_MSP_DIR
  export CORE_PEER_ADDRESS=peer0.certchain-${ORG}.svc.cluster.local:7051
  export CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_DIR/ca.crt

  # Install (tolerate "already exists" errors on re-runs)
  peer lifecycle chaincode install /work/${CC_NAME}.tar.gz 2>&1 || echo "  (may already be installed)"

  # Get package ID — use tail -1 to grab the LATEST installed package
  if [ -z "$PACKAGE_ID" ]; then
    PACKAGE_ID=$(peer lifecycle chaincode queryinstalled 2>&1 | grep "${CC_NAME}_${CC_VERSION}" | sed -n 's/.*Package ID: \(.*\), Label:.*/\1/p' | tail -1)
    echo "Package ID: $PACKAGE_ID"
  fi
done

if [ -z "$PACKAGE_ID" ]; then
  echo "ERROR: Could not determine package ID"
  exit 1
fi

# Save package ID to ConfigMap for chaincode deployment
# Central namespace (for reference / idempotency check)
$K create configmap chaincode-id \
  --from-literal=package-id="$PACKAGE_ID" \
  -n certchain --dry-run=client -o yaml | $K apply -f -
echo "Package ID saved to ConfigMap chaincode-id (central)"

# Per-org namespaces (each org's CcaaS deployment reads this)
for ORG in techpulse dataforge neuralpath; do
  $K create configmap chaincode-id \
    --from-literal=package-id="$PACKAGE_ID" \
    -n certchain-${ORG} --dry-run=client -o yaml | $K apply -f -
  echo "Package ID saved to ConfigMap chaincode-id (certchain-${ORG})"
done

# =================================================================
# Step 3: Approve chaincode for each org
# =================================================================
echo ""
echo "============================================="
echo "  Step 3: Approving chaincode for each org"
echo "============================================="

for ORG in techpulse dataforge neuralpath; do
  case $ORG in
    techpulse)  MSP_ID="TechPulseMSP" ;;
    dataforge)  MSP_ID="DataForgeMSP" ;;
    neuralpath) MSP_ID="NeuralPathMSP" ;;
  esac

  echo "--- Approving for ${ORG} (${MSP_ID}) ---"
  ORG_NS="certchain-${ORG}"
  ADMIN_MSP_DIR="/work/admin-msp-${ORG}"
  PEER_TLS_DIR="/work/peer-tls-${ORG}"

  export CORE_PEER_LOCALMSPID=$MSP_ID
  export CORE_PEER_MSPCONFIGPATH=$ADMIN_MSP_DIR
  export CORE_PEER_ADDRESS=peer0.certchain-${ORG}.svc.cluster.local:7051
  export CORE_PEER_TLS_ROOTCERT_FILE=$PEER_TLS_DIR/ca.crt

  APPROVE_OUT=$(peer lifecycle chaincode approveformyorg \
    --channelID $CHANNEL_NAME \
    --name $CC_NAME \
    --version $CC_VERSION \
    --package-id $PACKAGE_ID \
    --sequence $CC_SEQUENCE \
    --signature-policy "OR('TechPulseMSP.peer','DataForgeMSP.peer','NeuralPathMSP.peer')" \
    --orderer $ORDERER_ENDPOINT \
    --tls \
    --cafile $ORDERER_CA 2>&1) || {
    if echo "$APPROVE_OUT" | grep -q "unchanged content"; then
      echo "  Already approved for ${ORG} (unchanged)"
    else
      echo "$APPROVE_OUT"
      exit 1
    fi
  }
  echo "  Approved for ${ORG}"
done

# =================================================================
# Step 4: Check commit readiness
# =================================================================
echo ""
echo "============================================="
echo "  Step 4: Checking commit readiness"
echo "============================================="
# Use last org's peer context
peer lifecycle chaincode checkcommitreadiness \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --version $CC_VERSION \
  --sequence $CC_SEQUENCE \
  --signature-policy "OR('TechPulseMSP.peer','DataForgeMSP.peer','NeuralPathMSP.peer')" 2>&1

# =================================================================
# Step 5: Commit chaincode definition
# =================================================================
echo ""
echo "============================================="
echo "  Step 5: Committing chaincode definition"
echo "============================================="
COMMIT_OUT=$(peer lifecycle chaincode commit \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME \
  --version $CC_VERSION \
  --sequence $CC_SEQUENCE \
  --signature-policy "OR('TechPulseMSP.peer','DataForgeMSP.peer','NeuralPathMSP.peer')" \
  --orderer $ORDERER_ENDPOINT \
  --tls \
  --cafile $ORDERER_CA \
  --peerAddresses peer0.certchain-techpulse.svc.cluster.local:7051 \
  --tlsRootCertFiles /work/peer-tls-techpulse/ca.crt \
  --peerAddresses peer0.certchain-dataforge.svc.cluster.local:7051 \
  --tlsRootCertFiles /work/peer-tls-dataforge/ca.crt \
  --peerAddresses peer0.certchain-neuralpath.svc.cluster.local:7051 \
  --tlsRootCertFiles /work/peer-tls-neuralpath/ca.crt 2>&1) || {
  if echo "$COMMIT_OUT" | grep -q "already committed"; then
    echo "  Chaincode already committed at sequence $CC_SEQUENCE"
  else
    echo "$COMMIT_OUT"
    exit 1
  fi
}
echo "Chaincode committed!"

# =================================================================
# Step 6: Verify
# =================================================================
echo ""
echo "============================================="
echo "  Step 6: Verifying chaincode"
echo "============================================="
peer lifecycle chaincode querycommitted \
  --channelID $CHANNEL_NAME \
  --name $CC_NAME 2>&1

echo ""
echo "============================================="
echo "  Chaincode lifecycle complete!"
echo "============================================="
