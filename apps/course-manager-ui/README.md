# course-manager-ui

React SPA for organisation registrars to manage course certificates. Features a dashboard with charts, a certificate issuance form, a searchable certificate list, and certificate revocation. Each organisation gets a branded instance via runtime configuration.

## Local Development

```bash
cd apps/course-manager-ui
npm install
npm run dev
```

Vite dev server starts on **port 5173** and proxies `/api` requests to `localhost:8080` (cert-admin-api).

## Run Tests

```bash
npm test
```

Tests use Vitest with React Testing Library and jsdom. Keycloak and API calls are mocked.

## Build Container

```bash
source ../../env.sh
podman build -t ${REGISTRY}/course-manager-ui:${IMAGE_TAG} .
```

The container runs an Express server on **port 8080** that serves the Vite build output and proxies API requests.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VITE_KEYCLOAK_URL` | Keycloak server URL | `http://localhost:8080` |
| `VITE_KEYCLOAK_REALM` | Keycloak realm name | `certchain` |
| `VITE_KEYCLOAK_CLIENT_ID` | OIDC client ID | `course-manager-ui` |
| `VITE_API_URL` | cert-admin-api base URL | `/api/v1` |
| `ORG_NAME` | Organisation display name (runtime) | — |
| `ORG_PRIMARY_COLOR` | Brand colour for the UI (runtime) | — |
