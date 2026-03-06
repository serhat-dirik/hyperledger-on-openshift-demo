import { vi } from 'vitest';
import '@testing-library/jest-dom/vitest';

// Mock keycloak-js
vi.mock('keycloak-js', () => ({
  default: vi.fn(() => ({
    init: vi.fn().mockResolvedValue(true),
    login: vi.fn(),
    logout: vi.fn(),
    token: 'mock-token',
    authenticated: true,
    isTokenExpired: vi.fn().mockReturnValue(false),
    updateToken: vi.fn().mockResolvedValue(true),
    tokenParsed: { preferred_username: 'testuser', org_id: 'techpulse' },
  })),
}));

// Mock the keycloak service module
vi.mock('../services/keycloak', () => ({
  initKeycloak: vi.fn().mockResolvedValue(true),
  getToken: vi.fn().mockResolvedValue('mock-token'),
  getKeycloak: vi.fn(() => ({
    token: 'mock-token',
    authenticated: true,
    tokenParsed: { preferred_username: 'testuser', org_id: 'techpulse' },
    logout: vi.fn(),
  })),
  keycloak: {
    token: 'mock-token',
    authenticated: true,
    tokenParsed: { preferred_username: 'testuser', org_id: 'techpulse' },
    logout: vi.fn(),
    isTokenExpired: vi.fn().mockReturnValue(false),
    updateToken: vi.fn().mockResolvedValue(true),
  },
}));

// Mock window.matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});
