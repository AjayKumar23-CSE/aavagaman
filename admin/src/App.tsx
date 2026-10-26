import { useCallback, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { logout } from './lib/api';
import { getDashboard } from './lib/dashboard';
import { useSocketConnection, useSocketEvents, useSocketStatus, type AdminAlertEvent, type SosAlertEvent } from './lib/socket';
import { toast } from './lib/toast';
import { shortId } from './lib/ui';

/** Dashboard tiles and the SOS badge share this poll (SPEC §13: auto-refresh every 30 s). */
export const DASHBOARD_REFRESH_MS = 30_000;

const NAV: { to: string; label: string; end?: boolean; badge?: 'sos' }[] = [
  { to: '/', label: 'Dashboard', end: true },
  { to: '/live', label: 'Live map' },
  { to: '/rides', label: 'Rides' },
  { to: '/drivers', label: 'Drivers' },
  { to: '/riders', label: 'Riders' },
  { to: '/fare-config', label: 'Fare config' },
  { to: '/service-areas', label: 'Service areas' },
  { to: '/reports', label: 'Reports' },
  { to: '/settlements', label: 'Settlements' },
  { to: '/sos', label: 'SOS', badge: 'sos' },
  { to: '/audit', label: 'Audit' },
  { to: '/settings', label: 'Settings' },
];

function alertText(e: AdminAlertEvent): string {
  switch (e.type) {
    case 'driver_suspended':
      return `Driver ${shortId(e.driver_id)} suspended (${e.reason ?? 'rule'})`;
    case 'otp_failed':
      return `Repeated wrong trip OTP on ride ${shortId(e.ride_id)} (${e.attempts ?? '?'} attempts)`;
    case 'double_payment':
      return `Second payment capture ignored on ride ${shortId(e.ride_id)}`;
    case 'payment_after_close':
      return `Payment received for ${e.ride_status ?? 'closed'} ride ${shortId(e.ride_id)}`;
    default:
      return `Alert: ${e.type}`;
  }
}

const SOCKET_LABEL: Record<ReturnType<typeof useSocketStatus>, string> = {
  connected: 'Live',
  connecting: 'Connecting…',
  reconnecting: 'Reconnecting…',
  offline: 'Offline',
};

export default function App() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [loggingOut, setLoggingOut] = useState(false);

  const dashboard = useQuery({ queryKey: ['dashboard'], queryFn: getDashboard, refetchInterval: DASHBOARD_REFRESH_MS });
  const openSos = dashboard.data?.open_sos ?? 0;

  // Keep the realtime channel open app-wide so SOS and operational alerts reach every page.
  useSocketConnection();
  const socketStatus = useSocketStatus();
  const onSos = useCallback(
    (e: SosAlertEvent) => {
      toast.alert(`SOS from ${e.role} on ride ${shortId(e.ride_id)}`, { label: 'Open SOS', to: '/sos' });
      void queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      void queryClient.invalidateQueries({ queryKey: ['sos'] });
    },
    [queryClient],
  );
  const onAlert = useCallback((e: AdminAlertEvent) => {
    const to = e.ride_id ? `/rides/${e.ride_id}` : e.driver_id ? `/drivers/${e.driver_id}` : undefined;
    toast.alert(alertText(e), to ? { label: e.ride_id ? 'Open ride' : 'Open driver', to } : undefined);
  }, []);
  useSocketEvents({ onSos, onAlert });

  async function onLogout() {
    setLoggingOut(true);
    try {
      await logout();
    } catch {
      // Tokens are cleared locally regardless; the server session expires on its own.
    }
    queryClient.clear();
    navigate('/login', { replace: true });
  }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <aside className="sticky top-0 flex h-screen w-56 shrink-0 flex-col border-r border-gray-200 bg-white p-4">
        <div className="mb-1 flex items-center gap-2.5">
          <img src="/logo.svg" alt="" className="h-9 w-9" />
          <div>
            <div className="text-base font-semibold leading-tight text-gray-900">Aavagaman</div>
            <div className="text-[10px] font-medium uppercase tracking-[0.18em] text-gray-500">Admin</div>
          </div>
        </div>
        <div className="mb-5 flex items-center gap-1.5 text-xs text-gray-500" title="Realtime connection">
          <span
            className={`inline-block h-2 w-2 rounded-full ${
              socketStatus === 'connected' ? 'bg-green-500' : socketStatus === 'offline' ? 'bg-gray-300' : 'bg-amber-400'
            }`}
          />
          {SOCKET_LABEL[socketStatus]}
        </div>
        <nav className="flex-1 space-y-0.5 overflow-y-auto">
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.end}
              className={({ isActive }) =>
                `flex items-center justify-between rounded px-3 py-2 text-sm ${
                  isActive ? 'bg-[#0F3D2E] text-white' : 'text-gray-700 hover:bg-gray-100'
                }`
              }
            >
              <span>{n.label}</span>
              {n.badge === 'sos' && openSos > 0 && (
                <span
                  className="inline-flex min-w-5 items-center justify-center rounded-full bg-red-600 px-1.5 text-xs font-semibold text-white"
                  aria-label={`${openSos} open SOS alerts`}
                >
                  {openSos}
                </span>
              )}
            </NavLink>
          ))}
        </nav>
        <button
          type="button"
          onClick={onLogout}
          disabled={loggingOut}
          className="rounded px-3 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 disabled:opacity-50"
        >
          {loggingOut ? 'Logging out…' : 'Log out'}
        </button>
      </aside>
      <main className="min-w-0 flex-1 p-8">
        <Outlet />
      </main>
    </div>
  );
}
