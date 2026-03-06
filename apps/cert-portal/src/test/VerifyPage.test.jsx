import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import VerifyPage from '../pages/VerifyPage';

// Track navigation calls
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

function renderVerifyPage() {
  return render(
    <MemoryRouter initialEntries={['/']}>
      <VerifyPage />
    </MemoryRouter>,
  );
}

describe('VerifyPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders verify page with search input', () => {
    renderVerifyPage();

    expect(screen.getByText('Verify a Certificate')).toBeInTheDocument();
    expect(screen.getByLabelText('Certificate ID')).toBeInTheDocument();
    expect(
      screen.getByPlaceholderText('e.g. CERT-TP-20260115-0001'),
    ).toBeInTheDocument();
  });

  it('navigates to result page on submit', () => {
    renderVerifyPage();

    const input = screen.getByLabelText('Certificate ID');
    fireEvent.change(input, { target: { value: 'TEST-CERT-001' } });

    const button = screen.getByRole('button', { name: /verify certificate/i });
    fireEvent.click(button);

    expect(mockNavigate).toHaveBeenCalledWith('/result/TEST-CERT-001');
  });

  it('disables verify button when input is empty', () => {
    renderVerifyPage();

    const button = screen.getByRole('button', { name: /verify certificate/i });
    expect(button).toBeDisabled();
  });

  it('shows scan QR code link', () => {
    renderVerifyPage();

    const scanLink = screen.getByRole('link', { name: /scan qr code/i });
    expect(scanLink).toBeInTheDocument();
    expect(scanLink).toHaveAttribute('href', '/scan');
  });
});
