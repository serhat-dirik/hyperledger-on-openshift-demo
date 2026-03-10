import { getToken } from './keycloak';

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1';

async function authFetch(path, options = {}) {
  const token = await getToken();
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...options.headers,
    },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`API ${res.status}: ${body || res.statusText}`);
  }
  return res.json();
}

export function getDashboardStats() {
  return authFetch('/dashboard/stats');
}

export function getCertificates() {
  return authFetch('/certificates');
}

export function getCertificate(certId) {
  return authFetch(`/certificates/${certId}`);
}

export function issueCertificate(data) {
  return authFetch('/certificates', {
    method: 'POST',
    body: JSON.stringify(data),
  });
}

export function revokeCertificate(certId, reason) {
  return authFetch(`/certificates/${certId}/revoke`, {
    method: 'PUT',
    body: JSON.stringify({ reason }),
  });
}

export function getCourses() {
  return authFetch('/courses');
}

/**
 * Get the URL for a certificate's verification QR code (served by verify-api).
 * Uses VERIFY_API_URL from runtime config (/config.json) injected at deploy time.
 */
export function getQRCodeUrl(certId) {
  const verifyBase = window.__CONFIG__?.VERIFY_API_URL;
  if (!verifyBase) return null;
  return `${verifyBase}/${encodeURIComponent(certId)}/qr`;
}

export { API_BASE };
