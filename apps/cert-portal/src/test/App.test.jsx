import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import App from '../App';

// Mock the keycloak service module
vi.mock('../services/keycloak', () => ({
  initKeycloak: vi.fn(),
  isAuthenticated: vi.fn().mockReturnValue(false),
  login: vi.fn(),
  logout: vi.fn(),
  getToken: vi.fn().mockResolvedValue(null),
  getUserInfo: vi.fn().mockReturnValue(null),
  keycloak: null,
}));

import { initKeycloak } from '../services/keycloak';

describe('App', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows loading spinner before KC init', () => {
    // initKeycloak never resolves — stuck in loading
    initKeycloak.mockReturnValue(new Promise(() => {}));

    render(<App />);

    const spinner = document.querySelector('.animate-spin');
    expect(spinner).toBeInTheDocument();

    // Main content should not be rendered yet
    expect(screen.queryByText('CertChain')).not.toBeInTheDocument();
  });

  it('renders app after KC init', async () => {
    initKeycloak.mockResolvedValue(false);

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('CertChain')).toBeInTheDocument();
    });

    // The Portal suffix text should be visible
    expect(screen.getByText('Portal')).toBeInTheDocument();
  });

  it('shows bottom navigation', async () => {
    initKeycloak.mockResolvedValue(false);

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('CertChain')).toBeInTheDocument();
    });

    // Bottom nav links for anonymous user (no Transcript)
    expect(screen.getByText('Verify')).toBeInTheDocument();
    expect(screen.getByText('Scan')).toBeInTheDocument();
    expect(screen.getByText('About')).toBeInTheDocument();
  });
});
