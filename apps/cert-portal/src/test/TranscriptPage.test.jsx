import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import TranscriptPage from '../pages/TranscriptPage';

// Mock the keycloak service module
vi.mock('../services/keycloak', () => ({
  initKeycloak: vi.fn().mockResolvedValue(false),
  isAuthenticated: vi.fn().mockReturnValue(false),
  login: vi.fn(),
  logout: vi.fn(),
  getToken: vi.fn().mockResolvedValue(null),
  getUserInfo: vi.fn().mockReturnValue(null),
  keycloak: null,
}));

import { getToken, getUserInfo } from '../services/keycloak';

function renderTranscriptPage() {
  return render(
    <MemoryRouter initialEntries={['/transcript']}>
      <TranscriptPage />
    </MemoryRouter>,
  );
}

describe('TranscriptPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.restoreAllMocks();
  });

  it('shows loading state', () => {
    // getToken never resolves so we stay in loading
    getToken.mockReturnValue(new Promise(() => {}));
    getUserInfo.mockReturnValue({ name: 'Test User', email: 'test@example.com' });

    renderTranscriptPage();

    // The loading spinner is a div with animate-spin class; check it is present
    const spinner = document.querySelector('.animate-spin');
    expect(spinner).toBeInTheDocument();
  });

  it('displays certificates when loaded', async () => {
    const mockCerts = [
      {
        certID: 'CERT-TP-001',
        courseName: 'Full-Stack Web Dev',
        orgName: 'TechPulse Academy',
        status: 'ACTIVE',
        issueDate: '2026-01-15',
        expiryDate: '2028-01-15',
      },
      {
        certID: 'CERT-DF-001',
        courseName: 'PostgreSQL Administration',
        orgName: 'DataForge Institute',
        status: 'ACTIVE',
        issueDate: '2026-02-01',
        expiryDate: null,
      },
    ];

    getToken.mockResolvedValue('mock-jwt-token');
    getUserInfo.mockReturnValue({ name: 'Alice Johnson', email: 'alice@techpulse.dev' });

    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockCerts),
    });

    renderTranscriptPage();

    await waitFor(() => {
      expect(screen.getByText('Full-Stack Web Dev')).toBeInTheDocument();
    });

    expect(screen.getByText('PostgreSQL Administration')).toBeInTheDocument();
    expect(screen.getByText('TechPulse Academy')).toBeInTheDocument();
    expect(screen.getByText('DataForge Institute')).toBeInTheDocument();
    expect(screen.getByText('My Transcript')).toBeInTheDocument();
    expect(screen.getByText(/Alice Johnson/)).toBeInTheDocument();
  });

  it('shows error when auth fails', async () => {
    getToken.mockResolvedValue(null);
    getUserInfo.mockReturnValue(null);

    renderTranscriptPage();

    await waitFor(() => {
      expect(screen.getByText('Authentication required')).toBeInTheDocument();
    });

    expect(screen.getByText('Failed to load transcript')).toBeInTheDocument();
  });

  it('shows empty state when no certs', async () => {
    getToken.mockResolvedValue('mock-jwt-token');
    getUserInfo.mockReturnValue({ name: 'New Student', email: 'new@example.com' });

    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve([]),
    });

    renderTranscriptPage();

    await waitFor(() => {
      expect(screen.getByText('No certificates found')).toBeInTheDocument();
    });
  });
});
