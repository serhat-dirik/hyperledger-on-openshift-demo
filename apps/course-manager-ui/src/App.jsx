import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { initKeycloak, getKeycloak } from './services/keycloak';
import Layout from './components/Layout';
import Dashboard from './pages/Dashboard';
import IssueCertificate from './pages/IssueCertificate';
import CertificateList from './pages/CertificateList';
import CertificateDetail from './pages/CertificateDetail';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 1 },
  },
});

export default function App() {
  const [authenticated, setAuthenticated] = useState(false);
  const [accessDenied, setAccessDenied] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    initKeycloak()
      .then((auth) => {
        if (auth) {
          const kc = getKeycloak();
          const roles = kc.tokenParsed?.realm_access?.roles || [];
          if (!roles.includes('org-admin')) {
            setAccessDenied(true);
            return;
          }
          setAuthenticated(true);
        } else {
          setError('Authentication failed. Please try again.');
        }
      })
      .catch((err) => {
        console.error('Keycloak init error', err);
        // If URL contains stale auth params (e.g. after server restart),
        // clear them and retry once instead of showing an error.
        const url = new URL(window.location.href);
        if (url.searchParams.has('code') || url.searchParams.has('state') ||
            url.searchParams.has('session_state')) {
          url.searchParams.delete('code');
          url.searchParams.delete('state');
          url.searchParams.delete('session_state');
          url.searchParams.delete('iss');
          window.history.replaceState({}, '', url.pathname);
          window.location.reload();
          return;
        }
        setError('Unable to connect to authentication server.');
      });
  }, []);

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="bg-white rounded-lg shadow p-8 max-w-md text-center">
          <h1 className="text-xl font-semibold text-red-600 mb-2">
            Authentication Error
          </h1>
          <p className="text-gray-600">{error}</p>
          <button
            onClick={() => window.location.reload()}
            className="mt-4 px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 transition-colors cursor-pointer"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (accessDenied) {
    const kc = getKeycloak();
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="bg-white rounded-lg shadow p-8 max-w-md text-center">
          <h1 className="text-xl font-semibold text-red-600 mb-2">
            Access Denied
          </h1>
          <p className="text-gray-600 mb-1">
            This application is restricted to organization administrators.
          </p>
          <p className="text-sm text-gray-400 mb-4">
            Signed in as {kc.tokenParsed?.preferred_username || kc.tokenParsed?.email || 'unknown'}
          </p>
          <button
            onClick={() => kc.logout()}
            className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 transition-colors cursor-pointer"
          >
            Sign out
          </button>
        </div>
      </div>
    );
  }

  if (!authenticated) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-indigo-600 mx-auto mb-4" />
          <p className="text-gray-500">Connecting to CertChain...</p>
        </div>
      </div>
    );
  }

  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route element={<Layout />}>
            <Route path="/" element={<Dashboard />} />
            <Route path="/issue" element={<IssueCertificate />} />
            <Route path="/certs" element={<CertificateList />} />
            <Route path="/certs/:id" element={<CertificateDetail />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
