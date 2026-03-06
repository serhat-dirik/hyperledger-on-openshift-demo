import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import React from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import IssueCertificate from '../pages/IssueCertificate';
import { getCourses, issueCertificate } from '../services/api';

vi.mock('../services/api');

const mockCourses = [
  { courseID: 'COURSE-001', courseName: 'Full-Stack Web Dev' },
  { courseID: 'COURSE-002', courseName: 'Cloud-Native Microservices' },
  { courseID: 'COURSE-003', courseName: 'DevSecOps Fundamentals' },
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

describe('IssueCertificate', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getCourses.mockResolvedValue(mockCourses);
    issueCertificate.mockResolvedValue({ certID: 'CERT-TEST' });
  });

  it('renders issue form', async () => {
    renderWithProviders(<IssueCertificate />);

    expect(screen.getByText('Issue Certificate')).toBeInTheDocument();
    expect(screen.getByLabelText('Certificate ID')).toBeInTheDocument();
    expect(screen.getByLabelText('Student ID')).toBeInTheDocument();
    expect(screen.getByLabelText('Student Name')).toBeInTheDocument();
    expect(screen.getByLabelText('Course')).toBeInTheDocument();
    expect(screen.getByLabelText('Issue Date')).toBeInTheDocument();
    expect(screen.getByLabelText('Expiry Date')).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Issue Certificate' })
    ).toBeInTheDocument();
  });

  it('loads courses into dropdown', async () => {
    renderWithProviders(<IssueCertificate />);

    await waitFor(() => {
      expect(screen.getByText('Full-Stack Web Dev')).toBeInTheDocument();
    });
    expect(screen.getByText('Cloud-Native Microservices')).toBeInTheDocument();
    expect(screen.getByText('DevSecOps Fundamentals')).toBeInTheDocument();
  });

  it('submits form successfully', async () => {
    renderWithProviders(<IssueCertificate />);

    // Wait for courses to load
    await waitFor(() => {
      expect(screen.getByText('Full-Stack Web Dev')).toBeInTheDocument();
    });

    // Fill in the form
    fireEvent.change(screen.getByLabelText('Student ID'), {
      target: { value: 'STU-001' },
    });
    fireEvent.change(screen.getByLabelText('Student Name'), {
      target: { value: 'Alice Johnson' },
    });
    fireEvent.change(screen.getByLabelText('Course'), {
      target: { value: 'COURSE-001' },
    });

    // Submit the form
    fireEvent.click(screen.getByRole('button', { name: 'Issue Certificate' }));

    await waitFor(() => {
      expect(issueCertificate).toHaveBeenCalledTimes(1);
    });

    // Verify the call was made with correct data
    const callArgs = issueCertificate.mock.calls[0][0];
    expect(callArgs.studentID).toBe('STU-001');
    expect(callArgs.studentName).toBe('Alice Johnson');
    expect(callArgs.courseID).toBe('COURSE-001');
    expect(callArgs.courseName).toBe('Full-Stack Web Dev');
  });

  it('shows success message after submission', async () => {
    renderWithProviders(<IssueCertificate />);

    await waitFor(() => {
      expect(screen.getByText('Full-Stack Web Dev')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByLabelText('Student ID'), {
      target: { value: 'STU-001' },
    });
    fireEvent.change(screen.getByLabelText('Student Name'), {
      target: { value: 'Alice Johnson' },
    });
    fireEvent.change(screen.getByLabelText('Course'), {
      target: { value: 'COURSE-001' },
    });

    fireEvent.click(screen.getByRole('button', { name: 'Issue Certificate' }));

    await waitFor(() => {
      expect(screen.getByText(/issued successfully/)).toBeInTheDocument();
    });
  });

  it('shows error on failure', async () => {
    issueCertificate.mockRejectedValue(new Error('Ledger write failed'));

    renderWithProviders(<IssueCertificate />);

    await waitFor(() => {
      expect(screen.getByText('Full-Stack Web Dev')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByLabelText('Student ID'), {
      target: { value: 'STU-001' },
    });
    fireEvent.change(screen.getByLabelText('Student Name'), {
      target: { value: 'Alice Johnson' },
    });
    fireEvent.change(screen.getByLabelText('Course'), {
      target: { value: 'COURSE-001' },
    });

    fireEvent.click(screen.getByRole('button', { name: 'Issue Certificate' }));

    await waitFor(() => {
      expect(screen.getByText('Ledger write failed')).toBeInTheDocument();
    });
  });
});
