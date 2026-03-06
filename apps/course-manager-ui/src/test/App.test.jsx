import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import React from 'react';
import { initKeycloak } from '../services/keycloak';
import App from '../App';

describe('App', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows loading spinner before auth', () => {
    // initKeycloak returns a promise that never resolves during this test
    initKeycloak.mockReturnValue(new Promise(() => {}));

    render(<App />);

    expect(screen.getByText('Connecting to CertChain...')).toBeInTheDocument();
  });

  it('renders app after authentication', async () => {
    initKeycloak.mockResolvedValue(true);

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('Dashboard')).toBeInTheDocument();
    });
  });

  it('shows error when authentication fails', async () => {
    initKeycloak.mockResolvedValue(false);

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('Authentication Error')).toBeInTheDocument();
      expect(
        screen.getByText('Authentication failed. Please try again.')
      ).toBeInTheDocument();
    });
  });

  it('shows error when keycloak init throws', async () => {
    initKeycloak.mockRejectedValue(new Error('Network error'));

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('Authentication Error')).toBeInTheDocument();
      expect(
        screen.getByText('Unable to connect to authentication server.')
      ).toBeInTheDocument();
    });
  });
});
