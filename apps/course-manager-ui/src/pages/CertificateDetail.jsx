import React, { useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Award,
  CheckCircle,
  XCircle,
  Clock,
  AlertTriangle,
  QrCode,
  Download,
} from 'lucide-react';
import { getCertificate, revokeCertificate, getQRCodeUrl } from '../services/api';

const statusConfig = {
  ACTIVE: {
    bg: 'bg-emerald-100 text-emerald-700',
    icon: CheckCircle,
    iconColor: 'text-emerald-500',
  },
  REVOKED: {
    bg: 'bg-red-100 text-red-700',
    icon: XCircle,
    iconColor: 'text-red-500',
  },
  EXPIRED: {
    bg: 'bg-amber-100 text-amber-700',
    icon: Clock,
    iconColor: 'text-amber-500',
  },
};

function InfoRow({ label, value }) {
  return (
    <div className="py-3 flex justify-between border-b border-gray-100 last:border-0">
      <span className="text-sm text-gray-500">{label}</span>
      <span className="text-sm font-medium text-gray-900">{value || '--'}</span>
    </div>
  );
}

export default function CertificateDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [showRevoke, setShowRevoke] = useState(false);
  const [revokeReason, setRevokeReason] = useState('');

  const { data: cert, isLoading, error } = useQuery({
    queryKey: ['certificate', id],
    queryFn: () => getCertificate(id),
  });

  const revokeMutation = useMutation({
    mutationFn: ({ certId, reason }) => revokeCertificate(certId, reason),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['certificate', id] });
      queryClient.invalidateQueries({ queryKey: ['certificates'] });
      queryClient.invalidateQueries({ queryKey: ['dashboardStats'] });
      setShowRevoke(false);
      setRevokeReason('');
    },
  });

  if (isLoading) {
    return (
      <div className="p-8">
        <p className="text-gray-400">Loading certificate...</p>
      </div>
    );
  }

  if (error || !cert) {
    return (
      <div className="p-8">
        <div className="bg-red-50 text-red-700 p-4 rounded-lg">
          Certificate not found or failed to load.
        </div>
        <Link to="/certs" className="mt-4 inline-flex items-center gap-2 text-sm text-indigo-600">
          <ArrowLeft className="w-4 h-4" /> Back to certificates
        </Link>
      </div>
    );
  }

  const sc = statusConfig[cert.status] || statusConfig.ACTIVE;
  const StatusIcon = sc.icon;

  return (
    <div className="p-8 max-w-2xl">
      {/* Back link */}
      <Link
        to="/certs"
        className="inline-flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 mb-6"
      >
        <ArrowLeft className="w-4 h-4" /> Back to certificates
      </Link>

      {/* Header */}
      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <Award className="w-8 h-8 text-indigo-600" />
            <div>
              <h1 className="text-xl font-bold text-gray-900 font-mono">{cert.certID}</h1>
              <p className="text-sm text-gray-500 mt-0.5">{cert.courseName}</p>
            </div>
          </div>
          <span
            className={`inline-flex items-center gap-1.5 text-sm font-medium px-3 py-1.5 rounded-full ${sc.bg}`}
          >
            <StatusIcon className="w-4 h-4" />
            {cert.status}
          </span>
        </div>
      </div>

      {/* Details */}
      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Certificate Details</h2>
        <InfoRow label="Certificate ID" value={cert.certID} />
        <InfoRow label="Student ID" value={cert.studentID} />
        <InfoRow label="Student Name" value={cert.studentName} />
        <InfoRow label="Course" value={cert.courseName} />
        <InfoRow label="Issue Date" value={cert.issueDate} />
        <InfoRow label="Expiry Date" value={cert.expiryDate} />
        {cert.grade && <InfoRow label="Grade" value={cert.grade} />}
        {cert.degree && <InfoRow label="Degree" value={cert.degree} />}
        <InfoRow label="Organization" value={cert.orgID} />
        <InfoRow label="Status" value={cert.status} />
        {cert.revokeReason && <InfoRow label="Revoke Reason" value={cert.revokeReason} />}
      </div>

      {/* QR code for verification */}
      {getQRCodeUrl(cert.certID) && (
        <div className="bg-white rounded-lg shadow p-6 mb-6">
          <div className="flex items-center gap-2 mb-4">
            <QrCode className="w-5 h-5 text-indigo-600" />
            <h2 className="text-lg font-semibold text-gray-900">Verification QR Code</h2>
          </div>
          <div className="flex items-center gap-6">
            <img
              src={getQRCodeUrl(cert.certID)}
              alt={`QR code for ${cert.certID}`}
              className="w-36 h-36 border border-gray-200 rounded-lg"
            />
            <div className="space-y-2">
              <p className="text-sm text-gray-600">
                Scan this QR code to verify the certificate on the blockchain.
              </p>
              <a
                href={getQRCodeUrl(cert.certID)}
                download={`${cert.certID}-qr.png`}
                className="inline-flex items-center gap-1.5 text-sm font-medium text-indigo-600 hover:text-indigo-700"
              >
                <Download className="w-4 h-4" />
                Download QR Code
              </a>
            </div>
          </div>
        </div>
      )}

      {/* Revoke action */}
      {cert.status === 'ACTIVE' && (
        <div className="bg-white rounded-lg shadow p-6">
          {!showRevoke ? (
            <button
              onClick={() => setShowRevoke(true)}
              className="px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-md hover:bg-red-700 transition-colors cursor-pointer"
            >
              Revoke Certificate
            </button>
          ) : (
            <div>
              <div className="flex items-start gap-3 mb-4 p-3 bg-amber-50 rounded-lg">
                <AlertTriangle className="w-5 h-5 text-amber-600 mt-0.5 shrink-0" />
                <div>
                  <p className="text-sm font-medium text-amber-800">
                    Are you sure you want to revoke this certificate?
                  </p>
                  <p className="text-xs text-amber-600 mt-1">
                    This action is recorded on the blockchain and cannot be undone.
                  </p>
                </div>
              </div>

              <label htmlFor="revokeReason" className="block text-sm font-medium text-gray-700 mb-1">
                Reason for revocation
              </label>
              <textarea
                id="revokeReason"
                value={revokeReason}
                onChange={(e) => setRevokeReason(e.target.value)}
                required
                rows={3}
                placeholder="Provide a reason for revoking this certificate..."
                className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm mb-4 focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500"
              />

              <div className="flex gap-3">
                <button
                  onClick={() =>
                    revokeMutation.mutate({ certId: cert.certID, reason: revokeReason })
                  }
                  disabled={!revokeReason.trim() || revokeMutation.isPending}
                  className="px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-md hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors cursor-pointer"
                >
                  {revokeMutation.isPending ? 'Revoking...' : 'Confirm Revocation'}
                </button>
                <button
                  onClick={() => {
                    setShowRevoke(false);
                    setRevokeReason('');
                  }}
                  className="px-4 py-2 border border-gray-300 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-50 transition-colors cursor-pointer"
                >
                  Cancel
                </button>
              </div>

              {revokeMutation.isError && (
                <p className="text-sm text-red-600 mt-3">
                  Failed to revoke: {revokeMutation.error?.message || 'Unknown error'}
                </p>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
