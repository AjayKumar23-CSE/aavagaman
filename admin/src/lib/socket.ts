import { useEffect, useSyncExternalStore } from 'react';
import { io, type Socket } from 'socket.io-client';
import { API_BASE_URL, getAccessToken, refreshSession } from './api';
import type { LiveSnapshot } from './dashboard';

/**
 * One Socket.io connection to the `/rt` namespace (SPEC §8), shared by every
 * component that wants the `admin:live` stream or the alert events. The
 * connection is reference counted: it opens with the first subscriber and
 * closes shortly after the last one leaves.
 */

export type SocketStatus = 'connecting' | 'connected' | 'reconnecting' | 'offline';

export interface SosAlertEvent {
  sos_id: string;
  ride_id: string;
  user_id: string;
  role: 'rider' | 'driver';
  lat: number;
  lng: number;
  at: string;
}

export interface AdminAlertEvent {
  type: 'driver_suspended' | 'otp_failed' | 'double_payment' | 'payment_after_close' | (string & {});
  ride_id?: string;
  driver_id?: string;
  attempts?: number;
  reason?: string;
  gateway_payment_id?: string;
  ride_status?: string;
  at: string;
}

export interface RideStatusEvent {
  ride_id: string;
  status: string;
  [k: string]: unknown;
}

interface AlertHandlers {
  onSos?: (e: SosAlertEvent) => void;
  onAlert?: (e: AdminAlertEvent) => void;
  onRideStatus?: (e: RideStatusEvent) => void;
}

interface State {
  status: SocketStatus;
  snapshot: LiveSnapshot | null;
  /** Local receive time of the last snapshot (ms). */
  receivedAt: number | null;
}

let state: State = { status: 'offline', snapshot: null, receivedAt: null };
let socket: Socket | null = null;
let refs = 0;
let closeTimer: ReturnType<typeof setTimeout> | null = null;
const listeners = new Set<() => void>();
const handlers = new Set<AlertHandlers>();

function setState(patch: Partial<State>) {
  state = { ...state, ...patch };
  for (const l of listeners) l();
}

function open() {
  if (socket) return;
  setState({ status: 'connecting' });
  // `auth` as a function runs on every (re)connection attempt, so a refreshed token is picked up.
  const s = io(`${API_BASE_URL}/rt`, {
    auth: (cb) => cb({ token: getAccessToken() ?? '' }),
    transports: ['websocket'],
    reconnectionDelay: 1000,
    reconnectionDelayMax: 5000,
  });
  socket = s;

  s.on('connect', () => setState({ status: 'connected' }));
  s.on('disconnect', (reason) => {
    setState({ status: reason === 'io client disconnect' ? 'offline' : 'reconnecting' });
  });
  s.on('connect_error', (err) => {
    setState({ status: 'reconnecting' });
    if (err.message !== 'UNAUTHORIZED') return; // transport errors: the manager retries by itself
    // A middleware rejection stops automatic retries, so refresh the token and reconnect by hand.
    refreshSession()
      .then((ok) => {
        if (ok && socket === s) s.connect();
        else if (!ok) setState({ status: 'offline' });
      })
      .catch(() => setTimeout(() => socket === s && s.connect(), 3000));
  });
  s.on('admin:live', (snap: LiveSnapshot) => setState({ snapshot: snap, receivedAt: Date.now() }));
  s.on('sos:alert', (e: SosAlertEvent) => handlers.forEach((h) => h.onSos?.(e)));
  s.on('admin:alert', (e: AdminAlertEvent) => handlers.forEach((h) => h.onAlert?.(e)));
  s.on('ride:status', (e: RideStatusEvent) => handlers.forEach((h) => h.onRideStatus?.(e)));
}

function close() {
  socket?.disconnect();
  socket = null;
  setState({ status: 'offline' });
}

function acquire() {
  refs++;
  if (closeTimer) {
    clearTimeout(closeTimer);
    closeTimer = null;
  }
  open();
}

function release() {
  refs = Math.max(0, refs - 1);
  if (refs > 0) return;
  // Small grace period so StrictMode double-mounts and route changes do not reconnect.
  closeTimer = setTimeout(() => {
    closeTimer = null;
    if (refs === 0) close();
  }, 1000);
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

/** Keeps the shared socket open while the calling component is mounted. */
export function useSocketConnection(): void {
  useEffect(() => {
    acquire();
    return release;
  }, []);
}

export function useSocketStatus(): SocketStatus {
  return useSyncExternalStore(subscribe, () => state.status);
}

export function useLiveSnapshot(): { snapshot: LiveSnapshot | null; receivedAt: number | null } {
  const snapshot = useSyncExternalStore(subscribe, () => state.snapshot);
  const receivedAt = useSyncExternalStore(subscribe, () => state.receivedAt);
  return { snapshot, receivedAt };
}

/** Registers alert callbacks for as long as the component is mounted (does not open the socket by itself). */
export function useSocketEvents(h: AlertHandlers): void {
  const { onSos, onAlert, onRideStatus } = h;
  useEffect(() => {
    const entry: AlertHandlers = { onSos, onAlert, onRideStatus };
    handlers.add(entry);
    return () => {
      handlers.delete(entry);
    };
  }, [onSos, onAlert, onRideStatus]);
}
