import React, { useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Html5QrcodeScanner } from 'html5-qrcode';
import { Camera } from 'lucide-react';

/**
 * Extract a certificate ID from a scanned QR code value.
 * Supports two formats:
 *   1. URL containing /result/<certId>
 *   2. Raw cert ID string (e.g. "CERT-TP-20260115-0001")
 */
function extractCertId(text) {
  const urlMatch = text.match(/\/result\/([^/?#]+)/);
  if (urlMatch) {
    return decodeURIComponent(urlMatch[1]);
  }
  return text.trim();
}

export default function ScanPage() {
  const navigate = useNavigate();
  const scannerRef = useRef(null);
  const containerRef = useRef(null);

  useEffect(() => {
    // Small delay so the DOM node is available
    const timerId = setTimeout(() => {
      if (!containerRef.current) return;

      const scanner = new Html5QrcodeScanner(
        'qr-reader',
        {
          fps: 10,
          qrbox: { width: 250, height: 250 },
          rememberLastUsedCamera: true,
          aspectRatio: 1.0,
        },
        /* verbose= */ false,
      );

      scanner.render(
        (decodedText) => {
          const certId = extractCertId(decodedText);
          // Stop scanner before navigating
          scanner.clear().catch(() => {});
          navigate(`/result/${encodeURIComponent(certId)}`);
        },
        (errorMessage) => {
          // QR scan errors are expected while user is positioning camera
        },
      );

      scannerRef.current = scanner;
    }, 100);

    return () => {
      clearTimeout(timerId);
      if (scannerRef.current) {
        scannerRef.current.clear().catch(() => {});
        scannerRef.current = null;
      }
    };
  }, [navigate]);

  return (
    <div className="flex-1 flex flex-col items-center px-4 pt-6">
      <div className="w-full max-w-md space-y-4">
        {/* Header */}
        <div className="text-center space-y-1">
          <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-blue-100 mb-1">
            <Camera className="w-6 h-6 text-blue-600" />
          </div>
          <h2 className="text-xl font-bold text-gray-900">Scan QR Code</h2>
          <p className="text-gray-500 text-sm">
            Point your camera at a certificate QR code to verify it instantly.
          </p>
        </div>

        {/* Scanner container */}
        <div
          ref={containerRef}
          className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden"
        >
          <div id="qr-reader" className="w-full" />
        </div>

        <p className="text-center text-xs text-gray-400">
          Make sure the QR code is well-lit and within the scanning frame.
        </p>
      </div>
    </div>
  );
}
