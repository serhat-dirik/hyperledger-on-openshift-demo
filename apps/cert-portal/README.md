# cert-portal

Mobile-first React PWA for certificate verification. Employers verify certificates anonymously by entering a certificate ID or scanning a QR code. Students can optionally log in via Keycloak Identity Brokering to view their full transcript.

## Local Development

```bash
cd apps/cert-portal
npm install
npm run dev
```

Vite dev server starts on **port 5174** and proxies `/api` requests to `localhost:8081` (verify-api).

## Run Tests

```bash
npm test
```

Tests use Vitest with React Testing Library and jsdom. Keycloak and API calls are mocked.

## Build Container

```bash
source ../../env.sh
podman build -t ${REGISTRY}/cert-portal:${IMAGE_TAG} .
```

The container runs an Express server on **port 8080** that serves the PWA build output and proxies API requests.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VITE_KEYCLOAK_URL` | Central Keycloak server URL | `http://localhost:8080` |
| `VITE_KEYCLOAK_REALM` | Central Keycloak realm name | `certchain` |
| `VITE_KEYCLOAK_CLIENT_ID` | OIDC client ID | `cert-portal` |
| `VITE_VERIFY_API_URL` | verify-api base URL | `/api/v1/verify` |
| `VITE_TRANSCRIPT_API_URL` | Transcript API base URL | `/api/v1/transcript` |
