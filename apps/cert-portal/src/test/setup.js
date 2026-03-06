import { vi } from 'vitest';
import '@testing-library/jest-dom';

// Mock keycloak-js
vi.mock('keycloak-js', () => ({
  default: vi.fn(() => ({
    init: vi.fn().mockResolvedValue(false),
    login: vi.fn(),
    logout: vi.fn(),
    token: null,
    authenticated: false,
    isTokenExpired: vi.fn().mockReturnValue(true),
    updateToken: vi.fn().mockResolvedValue(false),
    tokenParsed: null,
  })),
}));

// Mock html5-qrcode
vi.mock('html5-qrcode', () => ({
  Html5QrcodeScanner: vi.fn().mockImplementation(() => ({
    render: vi.fn(),
    clear: vi.fn().mockResolvedValue(undefined),
  })),
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

// Mock import.meta.env
if (!import.meta.env) {
  import.meta.env = {};
}
