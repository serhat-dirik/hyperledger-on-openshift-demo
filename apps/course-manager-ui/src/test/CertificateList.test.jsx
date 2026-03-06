import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import React from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import CertificateList from '../pages/CertificateList';
import { getCertificates } from '../services/api';

vi.mock('../services/api');

const mockCertificates = [
  {
    certID: 'CERT-001',
    studentID: 'STU-001',
    studentName: 'Alice Johnson',
    courseName: 'Full-Stack Web Dev',
    status: 'ACTIVE',
    issueDate: '2025-11-01',
  },
  {
    certID: 'CERT-002',
    studentID: 'STU-002',
    studentName: 'Bob Smith',
    courseName: 'Cloud-Native Microservices',
    status: 'REVOKED',
    issueDate: '2025-10-15',
  },
  {
    certID: 'CERT-003',
    studentID: 'STU-003',
    studentName: 'Carol Davis',
    courseName: 'DevSecOps Fundamentals',
    status: 'ACTIVE',
    issueDate: '2025-09-20',
  },
];

function renderWithProviders(ui) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
    },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{ui}</MemoryRouter>
    </QueryClientProvider>
  );
}

describe('CertificateList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders certificate table', async () => {
    getCertificates.mockResolvedValue(mockCertificates);

    renderWithProviders(<CertificateList />);

    await waitFor(() => {
      expect(screen.getByText('CERT-001')).toBeInTheDocument();
    });
    expect(screen.getByText('CERT-002')).toBeInTheDocument();
    expect(screen.getByText('CERT-003')).toBeInTheDocument();

    // Verify table headers
    expect(screen.getByText('Cert ID')).toBeInTheDocument();
    expect(screen.getByText('Student')).toBeInTheDocument();
    expect(screen.getByText('Course')).toBeInTheDocument();
    expect(screen.getByText('Status')).toBeInTheDocument();
    expect(screen.getByText('Issue Date')).toBeInTheDocument();
  });

  it('filters certificates by search', async () => {
    getCertificates.mockResolvedValue(mockCertificates);

    renderWithProviders(<CertificateList />);

    await waitFor(() => {
      expect(screen.getByText('CERT-001')).toBeInTheDocument();
    });

    // All three certs visible
    expect(screen.getByText('CERT-002')).toBeInTheDocument();
    expect(screen.getByText('CERT-003')).toBeInTheDocument();

    // Type search query
    const searchInput = screen.getByPlaceholderText(
      'Search by ID, student, course, or status...'
    );
    fireEvent.change(searchInput, { target: { value: 'Alice' } });

    // Only Alice's cert should be visible
    expect(screen.getByText('CERT-001')).toBeInTheDocument();
    expect(screen.queryByText('CERT-002')).not.toBeInTheDocument();
    expect(screen.queryByText('CERT-003')).not.toBeInTheDocument();
  });

  it('filters by course name', async () => {
    getCertificates.mockResolvedValue(mockCertificates);

    renderWithProviders(<CertificateList />);

    await waitFor(() => {
      expect(screen.getByText('CERT-001')).toBeInTheDocument();
    });

    const searchInput = screen.getByPlaceholderText(
      'Search by ID, student, course, or status...'
    );
    fireEvent.change(searchInput, { target: { value: 'DevSecOps' } });

    expect(screen.queryByText('CERT-001')).not.toBeInTheDocument();
    expect(screen.queryByText('CERT-002')).not.toBeInTheDocument();
    expect(screen.getByText('CERT-003')).toBeInTheDocument();
  });

  it('shows empty state', async () => {
    getCertificates.mockResolvedValue([]);

    renderWithProviders(<CertificateList />);

    await waitFor(() => {
      expect(screen.getByText('No certificates found.')).toBeInTheDocument();
    });
  });

  it('shows no-match message when search has no results', async () => {
    getCertificates.mockResolvedValue(mockCertificates);

    renderWithProviders(<CertificateList />);

    await waitFor(() => {
      expect(screen.getByText('CERT-001')).toBeInTheDocument();
    });

    const searchInput = screen.getByPlaceholderText(
      'Search by ID, student, course, or status...'
    );
    fireEvent.change(searchInput, { target: { value: 'nonexistent' } });

    expect(
      screen.getByText('No certificates match your search.')
    ).toBeInTheDocument();
  });

  it('shows loading state', () => {
    getCertificates.mockReturnValue(new Promise(() => {}));

    renderWithProviders(<CertificateList />);

    expect(screen.getByText('Loading certificates...')).toBeInTheDocument();
  });

  it('displays certificate count', async () => {
    getCertificates.mockResolvedValue(mockCertificates);

    renderWithProviders(<CertificateList />);

    await waitFor(() => {
      expect(
        screen.getByText('Showing 3 of 3 certificates')
      ).toBeInTheDocument();
    });
  });
});
