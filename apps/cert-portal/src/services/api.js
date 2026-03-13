/**
 * API client for verify-api.
 * Public verification does not require authentication.
 * Authenticated students get enriched results (grade, degree).
 */
const API_BASE = import.meta.env.VITE_VERIFY_API_URL || '/api/v1/verify';

function getTranscriptBase() {
  return window.__PORTAL_CONFIG__?.TRANSCRIPT_API_URL
    || import.meta.env.VITE_TRANSCRIPT_API_URL
    || '/api/v1/transcript';
}

/**
 * Verify a certificate by its ID (public — no grade/degree).
 * @param {string} certId - The certificate identifier (e.g. "CERT-TP-20260101-0001")
 * @returns {Promise<Object>} Verification result with status, certificate details, and timestamp
 */
export async function verifyCertificate(certId) {
  const res = await fetch(`${API_BASE}/${encodeURIComponent(certId)}`);
  if (!res.ok) {
    if (res.status === 404) {
      return {
        status: 'NOT_FOUND',
        certId,
        message: 'Certificate not found on the blockchain ledger.',
      };
    }
    throw new Error(`Verification failed (HTTP ${res.status})`);
  }
  return res.json();
}

/**
 * Fetch full certificate detail including private fields (grade, degree).
 * Requires a valid JWT token. Falls back to public verify on failure.
 * @param {string} certId - The certificate identifier
 * @param {string} token - JWT bearer token
 * @returns {Promise<Object>} Full verification result with grade/degree
 */
export async function fetchCertificateDetail(certId, token) {
  const res = await fetch(`${getTranscriptBase()}/${encodeURIComponent(certId)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

/**
 * Get the URL for a certificate's QR code image.
 * @param {string} certId - The certificate identifier
 * @returns {string} QR code image URL
 */
export function getQRCodeUrl(certId) {
  return `${API_BASE}/${encodeURIComponent(certId)}/qr`;
}

export { API_BASE };
