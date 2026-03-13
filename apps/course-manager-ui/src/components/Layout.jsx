import React from 'react';
import { NavLink, Outlet } from 'react-router-dom';
import {
  LayoutDashboard,
  FilePlus,
  FileText,
  LogOut,
  Shield,
} from 'lucide-react';
import { keycloak } from '../services/keycloak';

const navItems = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/issue', label: 'Issue Certificate', icon: FilePlus },
  { to: '/certs', label: 'Certificates', icon: FileText },
];

export default function Layout() {
  const tokenParsed = keycloak.tokenParsed || {};
  const runtimeConfig = window.__CONFIG__ || {};
  const orgName = runtimeConfig.ORG_NAME || tokenParsed.org_name || tokenParsed.org_id || 'CertChain';
  const primaryColor = runtimeConfig.ORG_PRIMARY_COLOR || '#4f46e5';
  const userName = tokenParsed.name || tokenParsed.preferred_username || tokenParsed.email || 'Admin';

  return (
    <div className="min-h-screen flex bg-gray-50">
      {/* Sidebar */}
      <aside className="w-64 bg-gray-900 text-white flex flex-col shrink-0">
        <div className="p-6 border-b border-gray-700">
          <div className="flex items-center gap-2">
            <Shield className="w-6 h-6" style={{ color: primaryColor }} />
            <span className="text-lg font-bold">CertChain</span>
          </div>
          <p className="text-sm text-gray-400 mt-1">{orgName}</p>
          <div className="mt-2 h-0.5 rounded" style={{ backgroundColor: primaryColor }} />
        </div>

        <nav className="flex-1 py-4">
          {navItems.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                `flex items-center gap-3 px-6 py-3 text-sm transition-colors ${
                  isActive
                    ? 'bg-gray-800 text-white border-r-2'
                    : 'text-gray-400 hover:text-white hover:bg-gray-800'
                }`
              }
              style={({ isActive }) => isActive ? { borderColor: primaryColor } : {}}
            >
              <Icon className="w-5 h-5" />
              {label}
            </NavLink>
          ))}
        </nav>

        <div className="p-4 border-t border-gray-700">
          <div className="text-sm text-gray-400 mb-2 truncate">{userName}</div>
          <button
            onClick={() => keycloak.logout()}
            className="flex items-center gap-2 text-sm text-gray-400 hover:text-white transition-colors cursor-pointer"
          >
            <LogOut className="w-4 h-4" />
            Sign out
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-auto">
        <Outlet />
      </main>
    </div>
  );
}
