import React, { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import {
  ShieldCheck,
  ShieldX,
  AlertTriangle,
  HelpCircle,
  Loader2,
  AlertCircle,
  ArrowLeft,
  Search,
  Download,
} from 'lucide-react';
import { verifyCertificate, getQRCodeUrl } from '../services/api';

const STATUS_CONFIG = {
  VALID: {
    label: 'Valid',
    color: 'bg-green-50 border-green-200',
    iconBg: 'bg-green-100',
    iconColor: 'text-green-600',
    textColor: 'text-green-700',
    Icon: ShieldCheck,
  },
  ACTIVE: {
    label: 'Valid',
    color: 'bg-green-50 border-green-200',
    iconBg: 'bg-green-100',
    iconColor: 'text-green-600',
    textColor: 'text-green-700',
    Icon: ShieldCheck,
  },
  REVOKED: {
    label: 'Revoked',
    color: 'bg-red-50 border-red-200',
    iconBg: 'bg-red-100',
    iconColor: 'text-red-600',
    textColor: 'text-red-700',
    Icon: ShieldX,
  },
  EXPIRED: {
    label: 'Expired',
    color: 'bg-amber-50 border-amber-200',
    iconBg: 'bg-amber-100',
    iconColor: 'text-amber-600',
    textColor: 'text-amber-700',
    Icon: AlertTriangle,
  },
  NOT_FOUND: {
    label: 'Not Found',
    color: 'bg-gray-50 border-gray-200',
    iconBg: 'bg-gray-100',
    iconColor: 'text-gray-500',
    textColor: 'text-gray-600',
    Icon: HelpCircle,
  },
};

function DetailRow({ label, value }) {
  if (!value) return null;
  return (
    <div className="flex justify-between py-2 border-b border-gray-100 last:border-b-0">
      <span className="text-sm text-gray-500">{label}</span>
      <span className="text-sm font-medium text-gray-900 text-right ml-4">
        {value}
      </span>
    </div>
  );
}

function formatDate(dateStr) {
  if (!dateStr) return null;
  try {
    return new Date(dateStr).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  } catch {
    return dateStr;
  }
}

export default function ResultPage() {
  const { id: certId } = useParams();
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;

    async function verify() {
      setLoading(true);
      setError(null);
      try {
        const data = await verifyCertificate(certId);
        if (!cancelled) setResult(data);
      } catch (err) {
        if (!cancelled) setError(err.message || 'Verification request failed.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    verify();
    return () => {
      cancelled = true;
    };
  }, [certId]);

  // Loading state
  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center p-6">
        <div className="text-center space-y-3">
          <Loader2 className="w-10 h-10 text-blue-600 animate-spin mx-auto" />
          <p className="text-sm text-gray-500">Verifying on blockchain...</p>
        </div>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="flex-1 flex items-center justify-center p-6">
        <div className="w-full max-w-md text-center space-y-4">
          <div className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-red-100">
            <AlertCircle className="w-7 h-7 text-red-600" />
          </div>
          <h2 className="text-lg font-bold text-gray-900">
            Verification Failed
          </h2>
          <p className="text-sm text-gray-500">{error}</p>
          <Link
            to="/"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-blue-600 hover:text-blue-700"
          >
            <ArrowLeft className="w-4 h-4" />
            Try Again
          </Link>
        </div>
      </div>
    );
  }

  const status = result?.status || 'NOT_FOUND';
  const config = STATUS_CONFIG[status] || STATUS_CONFIG.NOT_FOUND;
  const { Icon, label, color, iconBg, iconColor, textColor } = config;

  const verifiedAt = new Date().toLocaleString('en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
  });

  return (
    <div className="flex-1 flex items-start justify-center px-4 pt-6">
      <div className="w-full max-w-md space-y-4">
        {/* Status badge card */}
        <div
          className={`rounded-xl border p-6 text-center space-y-3 ${color}`}
        >
          <div
            className={`inline-flex items-center justify-center w-16 h-16 rounded-full ${iconBg}`}
          >
            <Icon className={`w-8 h-8 ${iconColor}`} />
          </div>
          <h2 className={`text-2xl font-bold ${textColor}`}>{label}</h2>
          <p className="text-xs text-gray-500">Certificate ID: {certId}</p>
        </div>

        {/* Certificate details */}
        {status !== 'NOT_FOUND' && (
          <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-900 mb-3">
              Certificate Details
            </h3>
            <div className="divide-y divide-gray-100">
              <DetailRow
                label="Student Name"
                value={result?.studentName}
              />
              <DetailRow label="Course" value={result?.courseName} />
              <DetailRow
                label="Organization"
                value={result?.orgName}
              />
              <DetailRow
                label="Issue Date"
                value={formatDate(result?.issueDate)}
              />
              <DetailRow
                label="Expiry Date"
                value={formatDate(result?.expiryDate)}
              />
              {status === 'REVOKED' && (result?.revokeReason || result?.revocationReason) && (
                <div className="py-2">
                  <span className="text-sm text-gray-500">
                    Revocation Reason
                  </span>
                  <p className="text-sm font-medium text-red-700 mt-0.5">
                    {result.revokeReason || result.revocationReason}
                  </p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* QR code for sharing */}
        {status !== 'NOT_FOUND' && (
          <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-5 text-center space-y-3">
            <h3 className="text-sm font-semibold text-gray-900">
              Verification QR Code
            </h3>
            <img
              src={getQRCodeUrl(certId)}
              alt={`QR code for certificate ${certId}`}
              className="w-40 h-40 mx-auto"
            />
            <p className="text-xs text-gray-400">
              Scan to verify this certificate
            </p>
            <a
              href={getQRCodeUrl(certId)}
              download={`${certId}-qr.png`}
              className="inline-flex items-center gap-1.5 text-sm font-medium text-blue-600 hover:text-blue-700"
            >
              <Download className="w-4 h-4" />
              Download QR Code
            </a>
          </div>
        )}

        {/* Not found message */}
        {status === 'NOT_FOUND' && (
          <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-5 text-center space-y-2">
            <p className="text-sm text-gray-600">
              {result?.message ||
                'This certificate ID was not found on the blockchain ledger.'}
            </p>
            <p className="text-xs text-gray-400">
              Double-check the certificate ID and try again.
            </p>
          </div>
        )}

        {/* Verified at timestamp */}
        <p className="text-center text-xs text-gray-400">
          Verified at {verifiedAt}
        </p>

        {/* Action buttons */}
        <div className="space-y-2">
          <Link
            to="/"
            className="flex items-center justify-center gap-2 w-full py-3 px-4
                       bg-blue-600 text-white font-medium rounded-lg
                       hover:bg-blue-700 active:bg-blue-800 transition-colors text-sm"
          >
            <Search className="w-4 h-4" />
            Verify Another
          </Link>
        </div>
      </div>
    </div>
  );
}
