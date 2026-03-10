import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, NavLink, useLocation } from 'react-router-dom';
import { Search, QrCode, Info, ShieldCheck, FileText, LogIn, LogOut } from 'lucide-react';
import { initKeycloak, isAuthenticated, login, logout, getUserInfo, getIdpFromEmail } from './services/keycloak';
import VerifyPage from './pages/VerifyPage';
import ScanPage from './pages/ScanPage';
import ResultPage from './pages/ResultPage';
import TranscriptPage from './pages/TranscriptPage';

function LoginDialog({ onClose }) {
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');

  function handleSubmit(e) {
    e.preventDefault();
    const idp = getIdpFromEmail(email);
    if (idp) {
      login({ idpHint: idp });
    } else {
      setError('Please enter a valid organization email (e.g. you@techpulse.demo)');
    }
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={onClose}>
      <div
        className="bg-white rounded-xl shadow-xl p-6 w-full max-w-sm mx-4"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-lg font-bold text-gray-900 mb-1">Student Login</h2>
        <p className="text-sm text-gray-500 mb-4">
          Enter your organization email to sign in.
        </p>
        <form onSubmit={handleSubmit}>
          <input
            type="email"
            value={email}
            onChange={(e) => { setEmail(e.target.value); setError(''); }}
            placeholder="student@techpulse.demo"
            autoFocus
            required
            className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          />
          {error && <p className="text-xs text-red-500 mt-1.5">{error}</p>}
          <div className="flex gap-2 mt-4">
            <button
              type="submit"
              className="flex-1 bg-blue-600 text-white text-sm font-medium py-2 rounded-lg hover:bg-blue-700 transition-colors cursor-pointer"
            >
              Continue
            </button>
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800 transition-colors cursor-pointer"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function TopBar() {
  const authed = isAuthenticated();
  const userInfo = authed ? getUserInfo() : null;
  const [showLogin, setShowLogin] = useState(false);

  return (
    <>
      <header className="bg-blue-600 text-white px-4 py-3 flex items-center gap-2 shadow-md">
        <ShieldCheck className="w-6 h-6" />
        <h1 className="text-lg font-bold tracking-tight">CertChain</h1>
        <span className="text-blue-200 text-sm ml-1">Portal</span>
        <div className="flex-1" />
        {authed ? (
          <div className="flex items-center gap-3">
            <span className="text-sm text-blue-100 hidden sm:inline">
              {userInfo?.name}
            </span>
            <button
              onClick={logout}
              className="flex items-center gap-1 text-sm text-blue-200 hover:text-white transition-colors cursor-pointer"
            >
              <LogOut className="w-4 h-4" />
              <span className="hidden sm:inline">Sign out</span>
            </button>
          </div>
        ) : (
          <button
            onClick={() => setShowLogin(true)}
            className="flex items-center gap-1 text-sm bg-blue-500 hover:bg-blue-400 px-3 py-1.5 rounded-lg transition-colors cursor-pointer"
          >
            <LogIn className="w-4 h-4" />
            Student Login
          </button>
        )}
      </header>
      {showLogin && <LoginDialog onClose={() => setShowLogin(false)} />}
    </>
  );
}

function BottomNav() {
  const location = useLocation();
  const isResult = location.pathname.startsWith('/result');
  const authed = isAuthenticated();

  const linkBase =
    'flex flex-col items-center gap-0.5 py-2 px-3 text-xs font-medium transition-colors';
  const active = 'text-blue-600';
  const inactive = 'text-gray-400 hover:text-gray-600';

  return (
    <nav className="fixed bottom-0 inset-x-0 bg-white border-t border-gray-200 flex justify-around safe-bottom z-50">
      <NavLink
        to="/"
        className={({ isActive }) =>
          `${linkBase} ${isActive || isResult ? active : inactive}`
        }
      >
        <Search className="w-5 h-5" />
        <span>Verify</span>
      </NavLink>
      <NavLink
        to="/scan"
        className={({ isActive }) => `${linkBase} ${isActive ? active : inactive}`}
      >
        <QrCode className="w-5 h-5" />
        <span>Scan</span>
      </NavLink>
      {authed && (
        <NavLink
          to="/transcript"
          className={({ isActive }) => `${linkBase} ${isActive ? active : inactive}`}
        >
          <FileText className="w-5 h-5" />
          <span>Transcript</span>
        </NavLink>
      )}
      <NavLink
        to="/about"
        className={({ isActive }) => `${linkBase} ${isActive ? active : inactive}`}
      >
        <Info className="w-5 h-5" />
        <span>About</span>
      </NavLink>
    </nav>
  );
}

function AboutPage() {
  return (
    <div className="flex-1 flex items-center justify-center p-6">
      <div className="max-w-md text-center space-y-4">
        <ShieldCheck className="w-16 h-16 text-blue-600 mx-auto" />
        <h2 className="text-xl font-bold text-gray-900">CertChain Portal</h2>
        <p className="text-gray-600 text-sm leading-relaxed">
          CertChain provides tamper-proof certificate verification powered by
          Hyperledger Fabric blockchain. Certificates issued by accredited
          training institutes are anchored on-chain and can be verified instantly
          by students, employers, and auditors.
        </p>
        <p className="text-gray-500 text-sm leading-relaxed">
          Students can log in to access their full transcript, including course
          details and graduation information.
        </p>
        <div className="pt-2 text-xs text-gray-400">
          <p>Powered by Hyperledger Fabric</p>
          <p>Deployed on Red Hat OpenShift</p>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    initKeycloak().then(() => setReady(true));
  }, []);

  if (!ready) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
      </div>
    );
  }

  return (
    <BrowserRouter>
      <div className="min-h-screen bg-gray-50 flex flex-col pb-16">
        <TopBar />
        <main className="flex-1 flex flex-col">
          <Routes>
            <Route path="/" element={<VerifyPage />} />
            <Route path="/scan" element={<ScanPage />} />
            <Route path="/result/:id" element={<ResultPage />} />
            <Route path="/transcript" element={<TranscriptPage />} />
            <Route path="/about" element={<AboutPage />} />
          </Routes>
        </main>
        <BottomNav />
      </div>
    </BrowserRouter>
  );
}
