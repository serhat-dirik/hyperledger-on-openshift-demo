import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import { Award, CheckCircle, XCircle, Clock, ArrowRight } from 'lucide-react';
import { getDashboardStats, getCertificates } from '../services/api';

const statusColor = {
  ACTIVE: 'text-emerald-600 bg-emerald-50',
  REVOKED: 'text-red-600 bg-red-50',
  EXPIRED: 'text-amber-600 bg-amber-50',
};

function StatCard({ label, value, icon: Icon, color }) {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-gray-500">{label}</p>
          <p className="text-3xl font-bold mt-1">{value ?? '--'}</p>
        </div>
        <div className={`p-3 rounded-full ${color}`}>
          <Icon className="w-6 h-6" />
        </div>
      </div>
    </div>
  );
}

export default function Dashboard() {
  const statsQuery = useQuery({
    queryKey: ['dashboardStats'],
    queryFn: getDashboardStats,
  });

  const certsQuery = useQuery({
    queryKey: ['certificates'],
    queryFn: getCertificates,
  });

  const stats = statsQuery.data;
  const certs = certsQuery.data || [];
  const recentCerts = [...certs]
    .sort((a, b) => new Date(b.issueDate) - new Date(a.issueDate))
    .slice(0, 5);

  const chartData = [
    { name: 'Active', count: stats?.activeCerts ?? 0, fill: '#059669' },
    { name: 'Revoked', count: stats?.revokedCerts ?? 0, fill: '#dc2626' },
    { name: 'Expired', count: stats?.expiredCerts ?? 0, fill: '#d97706' },
  ];

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Dashboard</h1>

      {/* Stat cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <StatCard
          label="Total Certificates"
          value={stats?.totalCerts}
          icon={Award}
          color="text-indigo-600 bg-indigo-50"
        />
        <StatCard
          label="Active"
          value={stats?.activeCerts}
          icon={CheckCircle}
          color="text-emerald-600 bg-emerald-50"
        />
        <StatCard
          label="Revoked"
          value={stats?.revokedCerts}
          icon={XCircle}
          color="text-red-600 bg-red-50"
        />
      </div>

      {/* Chart */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">
            Certificates by Status
          </h2>
          {statsQuery.isLoading ? (
            <div className="h-64 flex items-center justify-center text-gray-400">
              Loading chart...
            </div>
          ) : (
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Bar dataKey="count" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </div>

        {/* Recent issuances */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-gray-900">
              Recent Issuances
            </h2>
            <Link
              to="/certs"
              className="text-sm text-indigo-600 hover:text-indigo-800 flex items-center gap-1"
            >
              View all <ArrowRight className="w-4 h-4" />
            </Link>
          </div>

          {certsQuery.isLoading ? (
            <p className="text-gray-400">Loading...</p>
          ) : recentCerts.length === 0 ? (
            <p className="text-gray-400">No certificates issued yet.</p>
          ) : (
            <ul className="divide-y divide-gray-100">
              {recentCerts.map((cert) => (
                <li key={cert.certID} className="py-3 flex items-center justify-between">
                  <div>
                    <Link
                      to={`/certs/${cert.certID}`}
                      className="text-sm font-medium text-gray-900 hover:text-indigo-600"
                    >
                      {cert.certID}
                    </Link>
                    <p className="text-xs text-gray-500">
                      {cert.studentName} &mdash; {cert.courseName}
                    </p>
                  </div>
                  <span
                    className={`text-xs font-medium px-2 py-1 rounded-full ${
                      statusColor[cert.status] || 'text-gray-600 bg-gray-100'
                    }`}
                  >
                    {cert.status}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}
