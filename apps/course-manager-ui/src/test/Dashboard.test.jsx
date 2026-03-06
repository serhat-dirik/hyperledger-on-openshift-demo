import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import React from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import Dashboard from '../pages/Dashboard';
import { getDashboardStats, getCertificates } from '../services/api';

vi.mock('../services/api');

// Mock recharts ResponsiveContainer since jsdom has no layout engine
vi.mock('recharts', async () => {
  const actual = await vi.importActual('recharts');
  return {
    ...actual,
    ResponsiveContainer: ({ children }) => (
      <div data-testid="responsive-container">{children}</div>
    ),
  };
});

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

const mockStats = {
  totalCerts: 42,
  activeCerts: 35,
  revokedCerts: 5,
  expiredCerts: 2,
};

const mockCertificates = [
  {
    certID: 'CERT-001',
    studentName: 'Alice Johnson',
    courseName: 'Full-Stack Web Dev',
    status: 'ACTIVE',
    issueDate: '2025-11-01',
  },
  {
    certID: 'CERT-002',
    studentName: 'Bob Smith',
    courseName: 'Cloud-Native Microservices',
    status: 'REVOKED',
    issueDate: '2025-10-15',
  },
];

describe('Dashboard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders dashboard heading', async () => {
    getDashboardStats.mockResolvedValue(mockStats);
    getCertificates.mockResolvedValue([]);

    renderWithProviders(<Dashboard />);

    expect(screen.getByText('Dashboard')).toBeInTheDocument();
  });

  it('displays stat cards when data loads', async () => {
    getDashboardStats.mockResolvedValue(mockStats);
    getCertificates.mockResolvedValue([]);

    renderWithProviders(<Dashboard />);

    await waitFor(() => {
      expect(screen.getByText('42')).toBeInTheDocument();
    });
    expect(screen.getByText('35')).toBeInTheDocument();
    expect(screen.getByText('5')).toBeInTheDocument();
    expect(screen.getByText('Total Certificates')).toBeInTheDocument();
    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText('Revoked')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    // Return promises that never resolve to keep loading state
    getDashboardStats.mockReturnValue(new Promise(() => {}));
    getCertificates.mockReturnValue(new Promise(() => {}));

    renderWithProviders(<Dashboard />);

    expect(screen.getByText('Loading chart...')).toBeInTheDocument();
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  it('displays recent certificates', async () => {
    getDashboardStats.mockResolvedValue(mockStats);
    getCertificates.mockResolvedValue(mockCertificates);

    renderWithProviders(<Dashboard />);

    await waitFor(() => {
      expect(screen.getByText('CERT-001')).toBeInTheDocument();
    });
    expect(screen.getByText('CERT-002')).toBeInTheDocument();
    expect(screen.getByText(/Alice Johnson/)).toBeInTheDocument();
    expect(screen.getByText(/Bob Smith/)).toBeInTheDocument();
  });

  it('shows empty state when no certificates exist', async () => {
    getDashboardStats.mockResolvedValue(mockStats);
    getCertificates.mockResolvedValue([]);

    renderWithProviders(<Dashboard />);

    await waitFor(() => {
      expect(screen.getByText('No certificates issued yet.')).toBeInTheDocument();
    });
  });
});
