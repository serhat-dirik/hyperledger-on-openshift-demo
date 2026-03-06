# cert-admin-api

Quarkus REST API for organisation administrators to issue, list, and revoke course certificates on the Hyperledger Fabric ledger. Each organisation deploys its own instance, scoped by the `org_id` claim in the Keycloak JWT.

## Local Development

```bash
cd apps/cert-admin-api
./mvnw quarkus:dev
```

Quarkus dev mode starts on **port 8080** with live-reload. A running Fabric peer (or the local `docker-compose` network) is required for ledger calls.

## Run Tests

```bash
./mvnw test
```

Tests use `@QuarkusTest` with a mocked `FabricGatewayClient`, so no blockchain is needed.

## Build Container

```bash
source ../../env.sh
podman build -t ${REGISTRY}/cert-admin-api:${IMAGE_TAG} .
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FABRIC_CHANNEL` | Fabric channel name | `certchannel` |
| `FABRIC_CHAINCODE` | Chaincode ID | `certcontract` |
| `FABRIC_PEER_ENDPOINT` | gRPC address of the org peer | `localhost:7051` |
| `FABRIC_MSP_ID` | Organisation MSP identifier | — |
| `FABRIC_CERT_PATH` | Path to admin enrollment certificate | — |
| `FABRIC_KEY_PATH` | Path to admin private key | — |
| `FABRIC_TLS_CERT_PATH` | Path to peer TLS CA certificate | — |
| `QUARKUS_OIDC_AUTH_SERVER_URL` | Keycloak realm URL | — |
| `QUARKUS_OIDC_CLIENT_ID` | OIDC client identifier | `cert-admin-api` |
