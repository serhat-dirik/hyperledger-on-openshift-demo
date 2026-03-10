import Keycloak from 'keycloak-js';

/**
 * Optional authentication for CertChain Portal.
 * Uses check-sso: app loads for everyone, but authenticated students
 * get access to rich transcript details.
 *
 * Students click "Login" → central KC → enter email →
 * KC Organizations detects domain → auto-redirects to org KC →
 * authenticate → back to central KC with session + JIT user provisioning.
 */
let keycloak;
let configLoaded = false;
let authenticated = false;

async function loadConfig() {
  if (configLoaded) return;
  try {
    const res = await fetch('/config.json');
    if (res.ok) {
      const cfg = await res.json();
      window.__PORTAL_CONFIG__ = cfg;
    }
  } catch {
    // config.json not available — fall back to env vars
  }
  configLoaded = true;
}

function getConfig(key, envKey, fallback) {
  return window.__PORTAL_CONFIG__?.[key]
    || import.meta.env[envKey]
    || fallback;
}

export async function initKeycloak() {
  await loadConfig();
  keycloak = new Keycloak({
    url: getConfig('KEYCLOAK_URL', 'VITE_KEYCLOAK_URL', 'http://localhost:8080'),
    realm: getConfig('KEYCLOAK_REALM', 'VITE_KEYCLOAK_REALM', 'certchain'),
    clientId: getConfig('KEYCLOAK_CLIENT_ID', 'VITE_KEYCLOAK_CLIENT_ID', 'cert-portal'),
  });

  try {
    authenticated = await keycloak.init({
      onLoad: 'check-sso',
      silentCheckSsoRedirectUri: window.location.origin + '/silent-check-sso.html',
      checkLoginIframe: false,
    });
  } catch (err) {
    console.warn('Keycloak init failed (continuing as anonymous):', err);
    authenticated = false;
  }

  return authenticated;
}

export function login(options) {
  if (keycloak) {
    keycloak.login(options);
  }
}

/**
 * Extract the IDP alias from a student's email address.
 * Domain pattern: user@<org>.demo → IDP alias is <org>
 * Returns null if the domain doesn't match the demo pattern.
 */
export function getIdpFromEmail(email) {
  const match = email?.match(/@([^.]+)\.demo$/i);
  return match ? match[1].toLowerCase() : null;
}

export function logout() {
  if (keycloak) {
    keycloak.logout({ redirectUri: window.location.origin });
  }
}

export function isAuthenticated() {
  return authenticated && keycloak?.authenticated;
}

export async function getToken() {
  if (!keycloak || !authenticated) return null;
  if (keycloak.isTokenExpired(30)) {
    try {
      await keycloak.updateToken(30);
    } catch {
      authenticated = false;
      return null;
    }
  }
  return keycloak.token;
}

export function getUserInfo() {
  if (!keycloak?.tokenParsed) return null;
  const tp = keycloak.tokenParsed;
  return {
    name: tp.name || tp.preferred_username || 'Student',
    email: tp.email,
    organization: tp.organization,
    roles: tp.realm_access?.roles || [],
  };
}

export { keycloak };
