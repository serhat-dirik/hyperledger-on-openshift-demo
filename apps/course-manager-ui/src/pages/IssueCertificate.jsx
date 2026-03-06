import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { FilePlus, CheckCircle, AlertCircle } from 'lucide-react';
import { issueCertificate, getCourses } from '../services/api';

function generateCertId() {
  const ts = Date.now().toString(36).toUpperCase();
  const rand = Math.random().toString(36).substring(2, 6).toUpperCase();
  return `CERT-${ts}-${rand}`;
}

function todayISO() {
  return new Date().toISOString().split('T')[0];
}

function oneYearFromNow() {
  const d = new Date();
  d.setFullYear(d.getFullYear() + 1);
  return d.toISOString().split('T')[0];
}

export default function IssueCertificate() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [form, setForm] = useState({
    certID: generateCertId(),
    studentID: '',
    studentName: '',
    courseID: '',
    issueDate: todayISO(),
    expiryDate: oneYearFromNow(),
  });

  const [feedback, setFeedback] = useState(null);
  const [errors, setErrors] = useState({});

  const coursesQuery = useQuery({
    queryKey: ['courses'],
    queryFn: getCourses,
  });

  const mutation = useMutation({
    mutationFn: issueCertificate,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['certificates'] });
      queryClient.invalidateQueries({ queryKey: ['dashboardStats'] });
      setFeedback({ type: 'success', message: `Certificate ${form.certID} issued successfully.` });
      setTimeout(() => navigate('/certs'), 2000);
    },
    onError: (err) => {
      setFeedback({ type: 'error', message: err.message || 'Failed to issue certificate.' });
    },
  });

  function validate() {
    const errs = {};
    if (!form.studentID.trim()) {
      errs.studentID = 'Student ID is required.';
    } else if (!/^[A-Za-z0-9][A-Za-z0-9._@-]{1,63}$/.test(form.studentID.trim())) {
      errs.studentID = 'Must be 2-64 characters: letters, numbers, hyphens, dots, or @.';
    }
    if (!form.studentName.trim()) {
      errs.studentName = 'Student name is required.';
    } else if (form.studentName.trim().length < 3 || !form.studentName.trim().includes(' ')) {
      errs.studentName = 'Enter a full name (first and last name).';
    }
    if (!form.courseID) {
      errs.courseID = 'Please select a course.';
    }
    if (form.expiryDate && form.issueDate && form.expiryDate <= form.issueDate) {
      errs.expiryDate = 'Expiry date must be after issue date.';
    }
    return errs;
  }

  function handleChange(e) {
    setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));
    // Clear error for the field being edited
    if (errors[e.target.name]) {
      setErrors((prev) => ({ ...prev, [e.target.name]: undefined }));
    }
  }

  function handleSubmit(e) {
    e.preventDefault();
    setFeedback(null);
    const errs = validate();
    if (Object.keys(errs).length > 0) {
      setErrors(errs);
      return;
    }
    setErrors({});
    const selectedCourse = courses.find((c) => c.courseID === form.courseID);
    mutation.mutate({ ...form, courseName: selectedCourse?.courseName || '' });
  }

  function handleRegenId() {
    setForm((prev) => ({ ...prev, certID: generateCertId() }));
  }

  const courses = coursesQuery.data || [];

  return (
    <div className="p-8 max-w-2xl">
      <div className="flex items-center gap-3 mb-6">
        <FilePlus className="w-6 h-6 text-indigo-600" />
        <h1 className="text-2xl font-bold text-gray-900">Issue Certificate</h1>
      </div>

      {feedback && (
        <div
          className={`mb-6 p-4 rounded-lg flex items-start gap-3 ${
            feedback.type === 'success'
              ? 'bg-emerald-50 text-emerald-800'
              : 'bg-red-50 text-red-800'
          }`}
        >
          {feedback.type === 'success' ? (
            <CheckCircle className="w-5 h-5 mt-0.5 shrink-0" />
          ) : (
            <AlertCircle className="w-5 h-5 mt-0.5 shrink-0" />
          )}
          <p className="text-sm">{feedback.message}</p>
        </div>
      )}

      <form onSubmit={handleSubmit} className="bg-white rounded-lg shadow p-6 space-y-5">
        {/* Certificate ID */}
        <div>
          <label htmlFor="certID" className="block text-sm font-medium text-gray-700 mb-1">
            Certificate ID
          </label>
          <div className="flex gap-2">
            <input
              id="certID"
              name="certID"
              value={form.certID}
              onChange={handleChange}
              required
              className="flex-1 rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
            />
            <button
              type="button"
              onClick={handleRegenId}
              className="px-3 py-2 text-sm text-indigo-600 border border-indigo-300 rounded-md hover:bg-indigo-50 transition-colors cursor-pointer"
            >
              Regenerate
            </button>
          </div>
        </div>

        {/* Student ID */}
        <div>
          <label htmlFor="studentID" className="block text-sm font-medium text-gray-700 mb-1">
            Student ID
          </label>
          <input
            id="studentID"
            name="studentID"
            value={form.studentID}
            onChange={handleChange}
            required
            pattern="^[A-Za-z0-9][A-Za-z0-9._@\-]{1,63}$"
            placeholder="e.g. student01@techpulse.demo"
            className={`w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 ${
              errors.studentID ? 'border-red-400 bg-red-50' : 'border-gray-300'
            }`}
          />
          {errors.studentID && (
            <p className="text-xs text-red-600 mt-1">{errors.studentID}</p>
          )}
        </div>

        {/* Student Name */}
        <div>
          <label htmlFor="studentName" className="block text-sm font-medium text-gray-700 mb-1">
            Student Name
          </label>
          <input
            id="studentName"
            name="studentName"
            value={form.studentName}
            onChange={handleChange}
            required
            minLength={3}
            placeholder="First and Last name"
            className={`w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 ${
              errors.studentName ? 'border-red-400 bg-red-50' : 'border-gray-300'
            }`}
          />
          {errors.studentName && (
            <p className="text-xs text-red-600 mt-1">{errors.studentName}</p>
          )}
        </div>

        {/* Course */}
        <div>
          <label htmlFor="courseID" className="block text-sm font-medium text-gray-700 mb-1">
            Course
          </label>
          <select
            id="courseID"
            name="courseID"
            value={form.courseID}
            onChange={handleChange}
            required
            className={`w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 ${
              errors.courseID ? 'border-red-400 bg-red-50' : 'border-gray-300'
            }`}
          >
            <option value="">Select a course...</option>
            {courses.map((c) => (
              <option key={c.courseID} value={c.courseID}>
                {c.courseName}
              </option>
            ))}
          </select>
          {errors.courseID && (
            <p className="text-xs text-red-600 mt-1">{errors.courseID}</p>
          )}
          {coursesQuery.isLoading && (
            <p className="text-xs text-gray-400 mt-1">Loading courses...</p>
          )}
        </div>

        {/* Dates */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label htmlFor="issueDate" className="block text-sm font-medium text-gray-700 mb-1">
              Issue Date
            </label>
            <input
              id="issueDate"
              name="issueDate"
              type="date"
              value={form.issueDate}
              onChange={handleChange}
              required
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
            />
          </div>
          <div>
            <label htmlFor="expiryDate" className="block text-sm font-medium text-gray-700 mb-1">
              Expiry Date
            </label>
            <input
              id="expiryDate"
              name="expiryDate"
              type="date"
              value={form.expiryDate}
              onChange={handleChange}
              required
              min={form.issueDate}
              className={`w-full rounded-md border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 ${
                errors.expiryDate ? 'border-red-400 bg-red-50' : 'border-gray-300'
              }`}
            />
            {errors.expiryDate && (
              <p className="text-xs text-red-600 mt-1">{errors.expiryDate}</p>
            )}
          </div>
        </div>

        {/* Submit */}
        <div className="pt-2">
          <button
            type="submit"
            disabled={mutation.isPending}
            className="w-full py-2.5 px-4 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors cursor-pointer"
          >
            {mutation.isPending ? 'Issuing...' : 'Issue Certificate'}
          </button>
        </div>
      </form>
    </div>
  );
}
