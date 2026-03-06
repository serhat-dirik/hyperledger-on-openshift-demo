import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = parseInt(process.env.PORT || '8080', 10);

// Runtime config from environment variables
const config = {
  VERIFY_API_URL: process.env.VERIFY_API_URL || '/api/v1/verify',
  TRANSCRIPT_API_URL: process.env.TRANSCRIPT_API_URL || '/api/v1/transcript',
  KEYCLOAK_URL: process.env.KEYCLOAK_URL || 'http://localhost:8080',
  KEYCLOAK_REALM: process.env.KEYCLOAK_REALM || 'certchain',
  KEYCLOAK_CLIENT_ID: process.env.KEYCLOAK_CLIENT_ID || 'cert-portal',
};

// Health endpoint
app.get('/health', (_req, res) => res.send('ok'));

// Runtime config endpoint
app.get('/config.json', (_req, res) => res.json(config));

// Proxy API calls to verify-api backend
// Use pathFilter (not mount path) to avoid Express stripping the /api prefix
app.use(createProxyMiddleware({
  target: `http://${process.env.API_BACKEND || 'verify-api:8080'}`,
  changeOrigin: true,
  pathFilter: '/api/**',
}));

// Serve static files
app.use(express.static(join(__dirname, 'dist')));

// SPA fallback — all other routes serve index.html (Express 5 syntax)
app.get('/{0,}', (_req, res) => {
  res.sendFile(join(__dirname, 'dist', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`cert-portal listening on port ${PORT}`);
  console.log(`Runtime config: ${JSON.stringify(config)}`);
});
