#!/usr/bin/env bash
set -euo pipefail
CHANNEL_NAME="certchannel"
ORDERER_ENDPOINT="orderer0:7050"

echo "TIMING_START $(date +%s)"
echo "============================================="
echo "  Channel Setup: $CHANNEL_NAME (BFT)"
echo "============================================="

# -------------------------------------------------------
# Step 1: Join ALL orderers to the channel via osnadmin
# BFT requires all 4 orderers to join before consensus starts.
# -------------------------------------------------------
echo ""
echo "=== [1/4] Joining orderers to channel (BFT: 4 nodes) ==="

# All orderers use certs from the same Fabric CA, so orderer0's
# TLS cert works as admin client cert for all orderers.
# Use FQDNs for org orderers because ExternalName aliases (orderer1, orderer2, orderer3)
# don't match the TLS certificate SANs (which list the actual service name "orderer").
ORDERER_ADMINS=(
  "orderer0:7053"
  "orderer.certchain-techpulse.svc.cluster.local:7053"
  "orderer.certchain-dataforge.svc.cluster.local:7053"
  "orderer.certchain-neuralpath.svc.cluster.local:7053"
)

for ADMIN_EP in "${ORDERER_ADMINS[@]}"; do
  ORDERER_NAME="${ADMIN_EP%%:*}"
  echo "--- Joining $ORDERER_NAME ---"
  osnadmin channel join \
    --channelID "$CHANNEL_NAME" \
    --config-block /channel-artifacts/genesis.block \
    -o "$ADMIN_EP" \
    --ca-file /orderer-tls/ca.crt \
    --client-cert /orderer-tls/server.crt \
    --client-key /orderer-tls/server.key 2>&1 || echo "  ($ORDERER_NAME may already be joined)"
done

# Wait for BFT consensus to form (need 3 of 4 orderers active)
echo ""
echo "Waiting for BFT consensus on orderer0..."
for i in $(seq 1 30); do
  STATUS=$(osnadmin channel list --channelID "$CHANNEL_NAME" \
    -o "orderer0:7053" \
    --ca-file /orderer-tls/ca.crt \
    --client-cert /orderer-tls/server.crt \
    --client-key /orderer-tls/server.key 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
  echo "  Attempt $i: status=$STATUS"
  if [ "$STATUS" = "active" ]; then
    echo "BFT consensus is active!"
    break
  fi
  sleep 3
done

# Verify all orderers joined
echo ""
echo "Verifying orderer channel membership:"
for ADMIN_EP in "${ORDERER_ADMINS[@]}"; do
  ORDERER_NAME="${ADMIN_EP%%:*}"
  osnadmin channel list \
    -o "$ADMIN_EP" \
    --ca-file /orderer-tls/ca.crt \
    --client-cert /orderer-tls/server.crt \
    --client-key /orderer-tls/server.key 2>/dev/null && echo "  [OK] $ORDERER_NAME" || echo "  [WARN] $ORDERER_NAME not reachable"
done

# -------------------------------------------------------
# Step 2: Fetch the genesis block for peer joins
# -------------------------------------------------------
echo ""
echo "=== [2/4] Fetching genesis block from orderer ==="
export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA=/orderer-tls/ca.crt

# Use TechPulse admin to fetch block
export CORE_PEER_LOCALMSPID=TechPulseMSP
export CORE_PEER_MSPCONFIGPATH=/admin-msp/techpulse
export CORE_PEER_ADDRESS=peer0-techpulse:7051
export CORE_PEER_TLS_ROOTCERT_FILE=/peer-tls/techpulse/ca.crt

# Retry fetching genesis block
FETCH_OK=false
for i in $(seq 1 10); do
  if peer channel fetch 0 /tmp/${CHANNEL_NAME}.block \
    -o "$ORDERER_ENDPOINT" \
    -c "$CHANNEL_NAME" \
    --tls \
    --cafile "$ORDERER_CA" 2>&1; then
    echo "Genesis block fetched successfully"
    FETCH_OK=true
    break
  fi
  echo "  Retry $i..."
  sleep 5
done
[ "$FETCH_OK" = "true" ] || { echo "ERROR: Could not fetch genesis block"; exit 1; }

# -------------------------------------------------------
# Step 3: Join peers to channel
# -------------------------------------------------------
echo ""
echo "=== [3/4] Joining peers to channel ==="

for ORG in techpulse dataforge neuralpath; do
  echo "--- Joining peer0 (${ORG}) ---"

  case $ORG in
    techpulse)  MSP_ID="TechPulseMSP" ;;
    dataforge)  MSP_ID="DataForgeMSP" ;;
    neuralpath) MSP_ID="NeuralPathMSP" ;;
  esac

  # Use FQDN because ExternalName alias peer0-{org} doesn't match TLS cert SAN (which is "peer0")
  PEER_FQDN="peer0.certchain-${ORG}.svc.cluster.local"

  export CORE_PEER_LOCALMSPID=$MSP_ID
  export CORE_PEER_MSPCONFIGPATH=/admin-msp/${ORG}
  export CORE_PEER_ADDRESS=${PEER_FQDN}:7051
  export CORE_PEER_TLS_ROOTCERT_FILE=/peer-tls/${ORG}/ca.crt

  peer channel join -b /tmp/${CHANNEL_NAME}.block 2>&1 || echo "  (peer may already be joined)"
  echo "peer0 (${ORG}) joined channel $CHANNEL_NAME"
done

# -------------------------------------------------------
# Step 4: Set anchor peers
# -------------------------------------------------------
echo ""
echo "=== [4/4] Setting anchor peers (best-effort) ==="
# Anchor peer updates require MAJORITY admin signatures.
# On re-runs when anchors are already set, this may fail — non-fatal.
set +e

for ORG in techpulse dataforge neuralpath; do
  echo "--- Setting anchor for ${ORG} ---"

  case $ORG in
    techpulse)  MSP_ID="TechPulseMSP" ;;
    dataforge)  MSP_ID="DataForgeMSP" ;;
    neuralpath) MSP_ID="NeuralPathMSP" ;;
  esac

  PEER_FQDN="peer0.certchain-${ORG}.svc.cluster.local"
  export CORE_PEER_LOCALMSPID=$MSP_ID
  export CORE_PEER_MSPCONFIGPATH=/admin-msp/${ORG}
  export CORE_PEER_ADDRESS=${PEER_FQDN}:7051
  export CORE_PEER_TLS_ROOTCERT_FILE=/peer-tls/${ORG}/ca.crt

  # Fetch current config
  peer channel fetch config /tmp/config_block.pb \
    -o "$ORDERER_ENDPOINT" -c "$CHANNEL_NAME" \
    --tls --cafile "$ORDERER_CA"

  # Extract and modify config to add anchor peer
  configtxlator proto_decode --input /tmp/config_block.pb --type common.Block \
    | jq '.data.data[0].payload.data.config' > /tmp/config.json

  ANCHOR_HOST="${PEER_FQDN}"

  # Check if anchor peer already set
  CURRENT=$(jq -r ".channel_group.groups.Application.groups.${MSP_ID}.values.AnchorPeers // empty" /tmp/config.json)
  if [ -n "$CURRENT" ] && [ "$CURRENT" != "null" ]; then
    echo "Anchor peer already set for $MSP_ID, updating..."
  fi

  jq ".channel_group.groups.Application.groups.${MSP_ID}.values.AnchorPeers = {
    \"mod_policy\": \"Admins\",
    \"value\": {
      \"anchor_peers\": [{
        \"host\": \"${ANCHOR_HOST}\",
        \"port\": 7051
      }]
    },
    \"version\": \"0\"
  }" /tmp/config.json > /tmp/modified_config.json

  configtxlator proto_encode --input /tmp/config.json --type common.Config --output /tmp/config.pb
  configtxlator proto_encode --input /tmp/modified_config.json --type common.Config --output /tmp/modified_config.pb
  configtxlator compute_update --channel_id "$CHANNEL_NAME" \
    --original /tmp/config.pb --updated /tmp/modified_config.pb --output /tmp/config_update.pb 2>/dev/null || {
    echo "No anchor peer update needed for $MSP_ID (already correct)"
    continue
  }

  configtxlator proto_decode --input /tmp/config_update.pb --type common.ConfigUpdate \
    | jq '{"payload":{"header":{"channel_header":{"channel_id":"'"$CHANNEL_NAME"'","type":2}},"data":{"config_update":.}}}' \
    | configtxlator proto_encode --type common.Envelope --output /tmp/anchor_update.pb

  peer channel update -o "$ORDERER_ENDPOINT" -c "$CHANNEL_NAME" \
    -f /tmp/anchor_update.pb --tls --cafile "$ORDERER_CA" || echo "  (anchor peer update failed — may already be set)"
  echo "Anchor peer set for $MSP_ID: $ANCHOR_HOST:7051"
done

set -e
echo ""
echo "============================================="
echo "  Channel setup complete! (BFT: 4 orderers, 3 peers)"
echo "============================================="
echo "TIMING_END $(date +%s)"
