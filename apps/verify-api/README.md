# verify-api

Quarkus REST API for certificate verification. Provides public endpoints for employers to verify a certificate by ID (including QR-code image generation) and authenticated endpoints for students to retrieve their full transcript.

## Local Development

```bash
cd apps/verify-api
./mvnw quarkus:dev
```

Quarkus dev mode starts on **port 8080** with live-reload. A running Fabric peer is required for ledger queries.

## Run Tests

```bash
./mvnw test
```

Tests use `@QuarkusTest` with a mocked `FabricGatewayClient`, so no blockchain is needed.

## Build Container

```bash
source ../../env.sh
podman build -t ${REGISTRY}/verify-api:${IMAGE_TAG} .
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FABRIC_CHANNEL` | Fabric channel name | `certchannel` |
| `FABRIC_CHAINCODE` | Chaincode ID | `certcontract` |
| `FABRIC_PEER_ENDPOINT` | gRPC address of a peer | `localhost:7051` |
| `FABRIC_MSP_ID` | MSP identifier for the gateway | — |
| `FABRIC_CERT_PATH` | Path to enrollment certificate | — |
| `FABRIC_KEY_PATH` | Path to private key | — |
| `FABRIC_TLS_CERT_PATH` | Path to peer TLS CA certificate | — |
| `QUARKUS_OIDC_AUTH_SERVER_URL` | Central Keycloak realm URL (for transcript auth) | — |
| `QUARKUS_OIDC_CLIENT_ID` | OIDC client identifier | `verify-api` |
