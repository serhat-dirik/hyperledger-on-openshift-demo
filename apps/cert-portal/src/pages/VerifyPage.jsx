import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Search, QrCode, ShieldCheck } from 'lucide-react';

export default function VerifyPage() {
  const [certId, setCertId] = useState('');
  const navigate = useNavigate();

  function handleSubmit(e) {
    e.preventDefault();
    const trimmed = certId.trim();
    if (trimmed) {
      navigate(`/result/${encodeURIComponent(trimmed)}`);
    }
  }

  return (
    <div className="flex-1 flex items-start justify-center px-4 pt-8">
      <div className="w-full max-w-md space-y-6">
        {/* Hero */}
        <div className="text-center space-y-2">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-100 mb-2">
            <ShieldCheck className="w-8 h-8 text-blue-600" />
          </div>
          <h2 className="text-2xl font-bold text-gray-900">
            Verify a Certificate
          </h2>
          <p className="text-gray-500 text-sm">
            Enter a certificate ID or scan its QR code to verify authenticity on
            the blockchain.
          </p>
        </div>

        {/* Search card */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-5 space-y-4">
          <form onSubmit={handleSubmit} className="space-y-3">
            <label
              htmlFor="certId"
              className="block text-sm font-medium text-gray-700"
            >
              Certificate ID
            </label>
            <div className="relative">
              <input
                id="certId"
                type="text"
                value={certId}
                onChange={(e) => setCertId(e.target.value)}
                placeholder="e.g. CERT-TP-20260115-0001"
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg text-sm
                           focus:ring-2 focus:ring-blue-500 focus:border-blue-500
                           placeholder:text-gray-400"
                autoComplete="off"
              />
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            </div>
            <button
              type="submit"
              disabled={!certId.trim()}
              className="w-full py-3 px-4 bg-blue-600 text-white font-medium rounded-lg
                         hover:bg-blue-700 active:bg-blue-800 transition-colors
                         disabled:bg-gray-300 disabled:cursor-not-allowed text-sm"
            >
              Verify Certificate
            </button>
          </form>

          <div className="relative">
            <div className="absolute inset-0 flex items-center">
              <div className="w-full border-t border-gray-200" />
            </div>
            <div className="relative flex justify-center text-xs">
              <span className="bg-white px-3 text-gray-400 uppercase tracking-wide">
                or
              </span>
            </div>
          </div>

          <Link
            to="/scan"
            className="flex items-center justify-center gap-2 w-full py-3 px-4
                       border border-gray-300 rounded-lg text-sm font-medium
                       text-gray-700 hover:bg-gray-50 active:bg-gray-100 transition-colors"
          >
            <QrCode className="w-4 h-4" />
            Scan QR Code
          </Link>
        </div>

        {/* Hint */}
        <p className="text-center text-xs text-gray-400">
          Certificates are anchored on Hyperledger Fabric and verified in
          real time.
        </p>
      </div>
    </div>
  );
}
