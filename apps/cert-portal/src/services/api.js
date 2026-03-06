/**
 * API client for verify-api.
 * Public verification does not require authentication.
 */
const API_BASE = import.meta.env.VITE_VERIFY_API_URL || '/api/v1/verify';

/**
 * Verify a certificate by its ID.
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
 * Get the URL for a certificate's QR code image.
 * @param {string} certId - The certificate identifier
 * @returns {string} QR code image URL
 */
export function getQRCodeUrl(certId) {
  return `${API_BASE}/${encodeURIComponent(certId)}/qr`;
}

export { API_BASE };
