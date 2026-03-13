import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import ResultPage from '../pages/ResultPage';

// Mock the api module
vi.mock('../services/api', () => ({
  verifyCertificate: vi.fn(),
  fetchCertificateDetail: vi.fn(),
  getQRCodeUrl: vi.fn((id) => `/api/v1/verify/${id}/qr`),
}));

// Mock keycloak module
vi.mock('../services/keycloak', () => ({
  isAuthenticated: vi.fn(() => false),
  getToken: vi.fn(() => Promise.resolve(null)),
}));

import { verifyCertificate, fetchCertificateDetail } from '../services/api';
import { isAuthenticated, getToken } from '../services/keycloak';

function renderResultPage(certId = 'TEST-CERT-001') {
  return render(
    <MemoryRouter initialEntries={[`/result/${certId}`]}>
      <Routes>
        <Route path="/result/:id" element={<ResultPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('ResultPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows loading state', () => {
    // Never resolve so we stay in loading state
    verifyCertificate.mockReturnValue(new Promise(() => {}));

    renderResultPage();

    expect(screen.getByText('Verifying on blockchain...')).toBeInTheDocument();
  });

  it('displays valid certificate result', async () => {
    verifyCertificate.mockResolvedValue({
      status: 'VALID',
      certId: 'TEST-CERT-001',
      studentName: 'Alice Johnson',
      courseName: 'Full-Stack Web Dev',
      orgName: 'TechPulse Academy',
      issueDate: '2026-01-15',
      expiryDate: '2028-01-15',
    });

    renderResultPage();

    await waitFor(() => {
      expect(screen.getByText('Valid')).toBeInTheDocument();
    });

    expect(screen.getByText('Alice Johnson')).toBeInTheDocument();
    expect(screen.getByText('Full-Stack Web Dev')).toBeInTheDocument();
    expect(screen.getByText('TechPulse Academy')).toBeInTheDocument();
    expect(
      screen.getByText('Certificate ID: TEST-CERT-001'),
    ).toBeInTheDocument();
  });

  it('displays revoked certificate result', async () => {
    verifyCertificate.mockResolvedValue({
      status: 'REVOKED',
      certId: 'TEST-CERT-002',
      studentName: 'Bob Smith',
      courseName: 'Cloud-Native Microservices',
      orgName: 'TechPulse Academy',
      issueDate: '2025-06-01',
      revokeReason: 'Academic misconduct',
    });

    renderResultPage('TEST-CERT-002');

    await waitFor(() => {
      expect(screen.getByText('Revoked')).toBeInTheDocument();
    });

    expect(screen.getByText('Academic misconduct')).toBeInTheDocument();
    expect(screen.getByText('Bob Smith')).toBeInTheDocument();
  });

  it('displays not found result', async () => {
    verifyCertificate.mockResolvedValue({
      status: 'NOT_FOUND',
      certId: 'INVALID-ID',
      message: 'Certificate not found on the blockchain ledger.',
    });

    renderResultPage('INVALID-ID');

    await waitFor(() => {
      expect(screen.getByText('Not Found')).toBeInTheDocument();
    });

    expect(
      screen.getByText('Certificate not found on the blockchain ledger.'),
    ).toBeInTheDocument();
    expect(
      screen.getByText('Double-check the certificate ID and try again.'),
    ).toBeInTheDocument();
  });

  it('shows error on API failure', async () => {
    verifyCertificate.mockRejectedValue(new Error('Network error'));

    renderResultPage();

    await waitFor(() => {
      expect(screen.getByText('Verification Failed')).toBeInTheDocument();
    });

    expect(screen.getByText('Network error')).toBeInTheDocument();
    expect(screen.getByText('Try Again')).toBeInTheDocument();
  });

  it('shows grade and degree for authenticated students', async () => {
    isAuthenticated.mockReturnValue(true);
    getToken.mockResolvedValue('mock-jwt-token');
    fetchCertificateDetail.mockResolvedValue({
      status: 'VALID',
      certId: 'TEST-CERT-001',
      studentName: 'Alice Johnson',
      courseName: 'Full-Stack Web Dev',
      orgName: 'TechPulse Academy',
      issueDate: '2026-01-15',
      expiryDate: '2028-01-15',
      grade: 'A',
      degree: 'Professional Certificate',
    });

    renderResultPage();

    await waitFor(() => {
      expect(screen.getByText('Valid')).toBeInTheDocument();
    });

    // Private fields (grade, degree) shown in verification result
    expect(screen.getByText('Professional Certificate')).toBeInTheDocument();
    expect(screen.getByText(/Grade: A/)).toBeInTheDocument();
    expect(screen.getByText('Alice Johnson')).toBeInTheDocument();
  });

  it('falls back to public verify when authenticated fetch fails', async () => {
    isAuthenticated.mockReturnValue(true);
    getToken.mockResolvedValue('mock-jwt-token');
    fetchCertificateDetail.mockRejectedValue(new Error('403'));
    verifyCertificate.mockResolvedValue({
      status: 'VALID',
      certId: 'TEST-CERT-001',
      studentName: 'Alice Johnson',
      courseName: 'Full-Stack Web Dev',
      orgName: 'TechPulse Academy',
      issueDate: '2026-01-15',
      expiryDate: '2028-01-15',
    });

    renderResultPage();

    await waitFor(() => {
      expect(screen.getByText('Valid')).toBeInTheDocument();
    });

    // Public result — no grade/degree
    expect(screen.getByText('Alice Johnson')).toBeInTheDocument();
    expect(screen.queryByText(/Grade:/)).not.toBeInTheDocument();
  });
});
