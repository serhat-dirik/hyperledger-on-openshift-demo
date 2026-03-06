# certcontract

Go smart contract for Hyperledger Fabric that manages certificate lifecycle on the ledger. Supports issuing, querying, verifying, and revoking course certificates with full audit history.

## Chaincode Functions

| Function | Description |
|----------|-------------|
| `InitLedger` | Seed the ledger with sample certificates |
| `IssueCertificate` | Write a new certificate to the ledger |
| `GetCertificate` | Retrieve a certificate by ID |
| `VerifyCertificate` | Verify a certificate and return its status |
| `RevokeCertificate` | Revoke an active certificate with a reason |
| `GetCertificatesByStudent` | Query certificates by student ID |
| `GetCertificatesByOrg` | Query certificates by organisation ID |
| `GetCertificateHistory` | Return the full transaction history for a certificate |

Certificate states: `ACTIVE`, `REVOKED`, `EXPIRED`.

## Local Development

```bash
cd fabric/chaincode/certcontract
go build ./...
```

## Run Tests

```bash
go test ./... -v
```

Tests use the `mocks` package with a stubbed `ChaincodeStubInterface`.

## Build for CcaaS

The chaincode is deployed using the Chaincode-as-a-Service (CcaaS) pattern:

```bash
source ../../../env.sh
podman build -t ${REGISTRY}/certcontract:${IMAGE_TAG} .
```

## Key Implementation Details

- **Composite keys**: `CERT~orgID~certID` for efficient org-scoped queries
- **CouchDB rich queries**: Used for student and org lookups
- **State validation**: Prevents double-issue, revocation of non-active certs
