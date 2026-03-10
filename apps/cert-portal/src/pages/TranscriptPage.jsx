import React, { useState, useEffect } from 'react';
import { FileText, Award, Calendar, Building2, QrCode } from 'lucide-react';
import { getToken, getUserInfo } from '../services/keycloak';
import { getQRCodeUrl } from '../services/api';

export default function TranscriptPage() {
  const [certs, setCerts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const userInfo = getUserInfo();

  useEffect(() => {
    fetchTranscript();
  }, []);

  async function fetchTranscript() {
    try {
      const token = await getToken();
      if (!token) {
        setError('Authentication required');
        setLoading(false);
        return;
      }
      const config = window.__PORTAL_CONFIG__ || {};
      const baseUrl = config.TRANSCRIPT_API_URL
        || import.meta.env.VITE_TRANSCRIPT_API_URL
        || '/api/v1/transcript';

      const res = await fetch(baseUrl, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setCerts(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center p-6">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex-1 flex items-center justify-center p-6">
        <div className="text-center space-y-2">
          <p className="text-red-500 font-medium">Failed to load transcript</p>
          <p className="text-gray-500 text-sm">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 p-4 space-y-4">
      <div className="bg-white rounded-xl shadow-sm p-4 border border-gray-100">
        <h2 className="text-lg font-bold text-gray-900 flex items-center gap-2">
          <FileText className="w-5 h-5 text-blue-600" />
          My Transcript
        </h2>
        {userInfo && (
          <p className="text-sm text-gray-500 mt-1">
            {userInfo.name} — {userInfo.email}
          </p>
        )}
      </div>

      {certs.length === 0 ? (
        <div className="text-center py-12 text-gray-400">
          <Award className="w-12 h-12 mx-auto mb-3" />
          <p>No certificates found</p>
        </div>
      ) : (
        <div className="space-y-3">
          {certs.map((cert) => (
            <div
              key={cert.certID}
              className="bg-white rounded-xl shadow-sm p-4 border border-gray-100"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <h3 className="font-semibold text-gray-900">{cert.courseName}</h3>
                  <div className="flex items-center gap-1 mt-1 text-sm text-gray-500">
                    <Building2 className="w-3.5 h-3.5" />
                    <span>{cert.orgName}</span>
                  </div>
                  {cert.courseDescription && (
                    <p className="text-sm text-gray-600 mt-2">{cert.courseDescription}</p>
                  )}
                </div>
                <span
                  className={`text-xs font-medium px-2 py-1 rounded-full ${
                    cert.status === 'ACTIVE'
                      ? 'bg-green-100 text-green-700'
                      : cert.status === 'REVOKED'
                      ? 'bg-red-100 text-red-700'
                      : 'bg-yellow-100 text-yellow-700'
                  }`}
                >
                  {cert.status}
                </span>
              </div>
              <div className="mt-3 flex items-center gap-4 text-xs text-gray-400">
                <span className="flex items-center gap-1">
                  <Calendar className="w-3 h-3" />
                  Issued: {cert.issueDate}
                </span>
                {cert.expiryDate && <span>Expires: {cert.expiryDate}</span>}
              </div>
              <div className="mt-2 flex items-center justify-between">
                <span className="text-xs text-gray-400 font-mono">{cert.certID}</span>
                {cert.status === 'ACTIVE' && (
                  <a
                    href={getQRCodeUrl(cert.certID)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-xs font-medium text-blue-600 hover:text-blue-700"
                  >
                    <QrCode className="w-3.5 h-3.5" />
                    QR Code
                  </a>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
