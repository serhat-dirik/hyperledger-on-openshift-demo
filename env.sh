#!/usr/bin/env bash
# ============================================================================
# CertChain Demo — Runtime Configuration
# ============================================================================
# Minimal env file. Versions, resource limits, and credentials live in
# helm/components/*/values.yaml. Domain and registry are auto-detected by scripts.
# ============================================================================

# --- Namespace prefix (org namespaces are ${PROJECT_NAMESPACE}-<orgname>) ---
export PROJECT_NAMESPACE="certchain"

# --- Fabric channel name ---------------------------------------------------
export FABRIC_CHANNEL_NAME="certchannel"
