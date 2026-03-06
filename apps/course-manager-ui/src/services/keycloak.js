import Keycloak from 'keycloak-js';

/**
 * Runtime config is loaded from /config.json (injected by container entrypoint).
 * Falls back to VITE env vars or localhost defaults for local dev.
 */
let keycloak;
let configLoaded = false;

async function loadConfig() {
  if (configLoaded) return;
  try {
    const res = await fetch('/config.json');
    if (res.ok) {
      const cfg = await res.json();
      window.__CONFIG__ = cfg;
    }
  } catch {
    // config.json not available — fall back to env vars
  }
  configLoaded = true;
}

function getKeycloakUrl() {
  return window.__CONFIG__?.KEYCLOAK_URL
    || import.meta.env.VITE_KEYCLOAK_URL
    || 'http://localhost:8080';
}

function getKeycloakRealm() {
  return window.__CONFIG__?.KEYCLOAK_REALM
    || import.meta.env.VITE_KEYCLOAK_REALM
    || 'certchain';
}

export async function initKeycloak() {
  await loadConfig();
  const clientId = window.__CONFIG__?.KEYCLOAK_CLIENT_ID
    || import.meta.env.VITE_KEYCLOAK_CLIENT_ID
    || 'course-manager-ui';
  keycloak = new Keycloak({
    url: getKeycloakUrl(),
    realm: getKeycloakRealm(),
    clientId,
  });
  return keycloak.init({
    onLoad: 'login-required',
    checkLoginIframe: false,
  });
}

export async function getToken() {
  if (keycloak.isTokenExpired(30)) {
    try {
      await keycloak.updateToken(30);
    } catch (err) {
      console.error('Token refresh failed, redirecting to login', err);
      keycloak.login();
    }
  }
  return keycloak.token;
}

export function getKeycloak() {
  return keycloak;
}

export { keycloak };
