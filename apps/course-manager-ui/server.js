import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = parseInt(process.env.PORT || '8080', 10);

// Runtime config from environment variables
const config = {
  KEYCLOAK_URL: process.env.KEYCLOAK_URL || 'http://localhost:8080',
  KEYCLOAK_REALM: process.env.KEYCLOAK_REALM || 'certchain',
  KEYCLOAK_CLIENT_ID: process.env.KEYCLOAK_CLIENT_ID || 'course-manager-ui',
  API_URL: process.env.API_URL || '/api/v1',
  ORG_NAME: process.env.ORG_NAME || 'CertChain',
  ORG_ID: process.env.ORG_ID || 'certchain',
  ORG_PRIMARY_COLOR: process.env.ORG_PRIMARY_COLOR || '#4f46e5',
};

// Health endpoint
app.get('/health', (_req, res) => res.send('ok'));

// Runtime config endpoint
app.get('/config.json', (_req, res) => res.json(config));

// Proxy API calls to cert-admin-api backend
// Use pathFilter (not Express mount path) to avoid Express 5 stripping the prefix
app.use(createProxyMiddleware({
  target: `http://${process.env.API_BACKEND || 'cert-admin-api:8080'}`,
  changeOrigin: true,
  pathFilter: '/api/v1',
}));

// Serve static files
app.use(express.static(join(__dirname, 'dist')));

// SPA fallback — all other routes serve index.html (Express 5 syntax)
app.get('/{0,}', (_req, res) => {
  res.sendFile(join(__dirname, 'dist', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`course-manager-ui listening on port ${PORT}`);
  console.log(`Runtime config: ${JSON.stringify(config)}`);
});
