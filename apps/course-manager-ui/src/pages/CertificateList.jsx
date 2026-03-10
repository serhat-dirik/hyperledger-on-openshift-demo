import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { FileText, Search, ExternalLink, QrCode } from 'lucide-react';
import { getCertificates, getQRCodeUrl } from '../services/api';

const statusBadge = {
  ACTIVE: 'bg-emerald-100 text-emerald-700',
  REVOKED: 'bg-red-100 text-red-700',
  EXPIRED: 'bg-amber-100 text-amber-700',
};

export default function CertificateList() {
  const [search, setSearch] = useState('');

  const { data: certificates = [], isLoading } = useQuery({
    queryKey: ['certificates'],
    queryFn: getCertificates,
  });

  const filtered = certificates.filter((c) => {
    const q = search.toLowerCase();
    return (
      c.certID?.toLowerCase().includes(q) ||
      c.studentName?.toLowerCase().includes(q) ||
      c.courseName?.toLowerCase().includes(q) ||
      c.status?.toLowerCase().includes(q)
    );
  });

  return (
    <div className="p-8">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <FileText className="w-6 h-6 text-indigo-600" />
          <h1 className="text-2xl font-bold text-gray-900">Certificates</h1>
        </div>
        <Link
          to="/issue"
          className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700 transition-colors"
        >
          + Issue New
        </Link>
      </div>

      {/* Search */}
      <div className="relative mb-6 max-w-md">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by ID, student, course, or status..."
          className="w-full pl-10 pr-4 py-2 rounded-md border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
        />
      </div>

      {/* Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        {isLoading ? (
          <div className="p-8 text-center text-gray-400">Loading certificates...</div>
        ) : filtered.length === 0 ? (
          <div className="p-8 text-center text-gray-400">
            {search ? 'No certificates match your search.' : 'No certificates found.'}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50">
                <th className="text-left px-6 py-3 font-medium text-gray-500">Cert ID</th>
                <th className="text-left px-6 py-3 font-medium text-gray-500">Student</th>
                <th className="text-left px-6 py-3 font-medium text-gray-500">Course</th>
                <th className="text-left px-6 py-3 font-medium text-gray-500">Status</th>
                <th className="text-left px-6 py-3 font-medium text-gray-500">Issue Date</th>
                <th className="text-left px-6 py-3 font-medium text-gray-500">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtered.map((cert) => (
                <tr key={cert.certID} className="hover:bg-gray-50 transition-colors">
                  <td className="px-6 py-4 font-mono text-xs">{cert.certID}</td>
                  <td className="px-6 py-4">
                    <div className="font-medium text-gray-900">{cert.studentName}</div>
                    <div className="text-xs text-gray-400">{cert.studentID}</div>
                  </td>
                  <td className="px-6 py-4 text-gray-700">{cert.courseName}</td>
                  <td className="px-6 py-4">
                    <span
                      className={`text-xs font-medium px-2.5 py-1 rounded-full ${
                        statusBadge[cert.status] || 'bg-gray-100 text-gray-600'
                      }`}
                    >
                      {cert.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-gray-500">{cert.issueDate}</td>
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-3">
                      <Link
                        to={`/certs/${cert.certID}`}
                        className="text-indigo-600 hover:text-indigo-800 flex items-center gap-1"
                      >
                        <ExternalLink className="w-4 h-4" />
                        View
                      </Link>
                      {getQRCodeUrl(cert.certID) && (
                        <a
                          href={getQRCodeUrl(cert.certID)}
                          target="_blank"
                          rel="noopener noreferrer"
                          title="View QR code"
                          className="text-gray-400 hover:text-indigo-600 transition-colors"
                        >
                          <QrCode className="w-4 h-4" />
                        </a>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <p className="text-xs text-gray-400 mt-4">
        Showing {filtered.length} of {certificates.length} certificates
      </p>
    </div>
  );
}
