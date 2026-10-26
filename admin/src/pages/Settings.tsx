import { useState } from 'react';
import Card from '../components/Card';
import { changeAdminPassword, errorMessage } from '../lib/api';
import { toast } from '../lib/toast';
import { BTN_PRIMARY, INPUT, LABEL } from '../lib/ui';

const MIN_LENGTH = 10;

/** Mirrors the server rule so the admin sees the problem before submitting. */
function passwordProblem(pw: string): string | null {
  if (pw.length < MIN_LENGTH) return `At least ${MIN_LENGTH} characters.`;
  if (!/[A-Za-z]/.test(pw) || !/\d/.test(pw)) return 'Must contain at least one letter and one digit.';
  return null;
}

export default function Settings() {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const problem = next ? passwordProblem(next) : null;
  const mismatch = confirm.length > 0 && confirm !== next;
  const canSubmit = current.length > 0 && next.length > 0 && !problem && confirm === next && !busy;

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    if (!canSubmit) return;
    setBusy(true);
    setError(null);
    setDone(false);
    try {
      await changeAdminPassword(current, next);
      setDone(true);
      setCurrent('');
      setNext('');
      setConfirm('');
      toast.success('Password changed');
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">Settings</h1>
        <p className="text-sm text-gray-500">Account settings for the signed-in admin.</p>
      </div>

      <Card title="Change password" className="max-w-lg">
        <form onSubmit={submit} className="space-y-4">
          {done && (
            <p role="status" className="rounded-md bg-green-50 px-3 py-2 text-sm text-green-800">
              Password changed. Every other admin device was signed out; this session stays signed in.
            </p>
          )}
          <label className="block">
            <span className={LABEL}>Current password</span>
            <input
              type="password"
              required
              autoComplete="current-password"
              value={current}
              onChange={(e) => setCurrent(e.target.value)}
              className={INPUT}
            />
          </label>
          <label className="block">
            <span className={LABEL}>New password</span>
            <input
              type="password"
              required
              autoComplete="new-password"
              value={next}
              onChange={(e) => setNext(e.target.value)}
              className={INPUT}
              aria-describedby="pw-rule"
            />
            <span id="pw-rule" className={`mt-1 block text-xs ${problem ? 'text-red-600' : 'text-gray-500'}`}>
              {problem ?? `At least ${MIN_LENGTH} characters with a letter and a digit.`}
            </span>
          </label>
          <label className="block">
            <span className={LABEL}>Confirm new password</span>
            <input
              type="password"
              required
              autoComplete="new-password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              className={INPUT}
            />
            {mismatch && <span className="mt-1 block text-xs text-red-600">Passwords do not match.</span>}
          </label>
          {error && (
            <p role="alert" className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
              {error}
            </p>
          )}
          <div className="flex items-center justify-between gap-4">
            <p className="text-xs text-gray-500">Wrong current passwords count towards the login lockout.</p>
            <button type="submit" disabled={!canSubmit} className={BTN_PRIMARY}>
              {busy ? 'Saving…' : 'Change password'}
            </button>
          </div>
        </form>
      </Card>
    </div>
  );
}
