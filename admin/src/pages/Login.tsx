import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { adminLogin, errorMessage } from '../lib/api';

/** Only allow same-app paths as a post-login redirect target. */
function safeNext(next: string | null): string {
  return next && next.startsWith('/') && !next.startsWith('//') && !next.startsWith('/login') ? next : '/';
}

export default function Login() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await adminLogin(email.trim(), password);
      navigate(safeNext(params.get('next')), { replace: true });
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 p-4">
      <form
        onSubmit={submit}
        className="w-full max-w-sm space-y-4 rounded-lg border border-gray-200 bg-white p-6 shadow-sm"
      >
        <div className="flex items-center gap-3">
          <img src="/logo.svg" alt="" className="h-12 w-12" />
          <div>
            <h1 className="text-xl font-semibold text-gray-900">Aavagaman Admin</h1>
            <p className="text-sm text-gray-500">Safar • Aapke Saath — sign in to continue</p>
          </div>
        </div>
        <label className="block">
          <span className="mb-1 block text-sm font-medium text-gray-700">Email</span>
          <input
            type="email"
            required
            autoFocus
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-gray-900 focus:outline-none"
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-sm font-medium text-gray-700">Password</span>
          <input
            type="password"
            required
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-gray-900 focus:outline-none"
          />
        </label>
        {error && (
          <p role="alert" className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
            {error}
          </p>
        )}
        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-md bg-[#0F3D2E] px-4 py-2 text-sm font-medium text-white hover:bg-[#145C45] disabled:opacity-50"
        >
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
