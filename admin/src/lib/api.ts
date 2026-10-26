export const API_BASE_URL: string = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

/**
 * ngrok's free tier answers browser-looking requests with a warning page unless this
 * header is present (WebSocket upgrades are exempt). Sent only while the API is reached
 * through an ngrok tunnel, e.g. during phone testing from a laptop.
 */
const TUNNEL_HEADERS: Record<string, string> = /\.ngrok(-free)?\.(app|dev)\b/.test(API_BASE_URL)
  ? { 'ngrok-skip-browser-warning': '1' }
  : {};

export interface ApiErrorBody {
  error: { code: string; message: string; details?: string[] };
}

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details?: string[],
  ) {
    super(message);
  }
}

/** Human-readable message for any thrown value (validation details included). */
export function errorMessage(e: unknown): string {
  if (e instanceof ApiError) {
    return e.details?.length ? `${e.message}: ${e.details.join('; ')}` : e.message;
  }
  if (e instanceof Error) return e.message;
  return 'Something went wrong';
}

// ---------------------------------------------------------------------------
// Session tokens. Access token lives in memory only; the refresh token is kept
// in localStorage so a reload can silently re-establish the session.
// ---------------------------------------------------------------------------

const REFRESH_KEY = 'ride.admin.refresh';

export interface TokenPair {
  access_token: string;
  refresh_token: string;
}

let accessToken: string | null = null;

function readRefreshToken(): string | null {
  try {
    return localStorage.getItem(REFRESH_KEY);
  } catch {
    return null;
  }
}

function writeRefreshToken(token: string | null): void {
  try {
    if (token) localStorage.setItem(REFRESH_KEY, token);
    else localStorage.removeItem(REFRESH_KEY);
  } catch {
    // Storage blocked: the session still works for this page load.
  }
}

export function setTokens(tokens: TokenPair): void {
  accessToken = tokens.access_token;
  writeRefreshToken(tokens.refresh_token);
}

export function clearTokens(): void {
  accessToken = null;
  writeRefreshToken(null);
}

export function hasAccessToken(): boolean {
  return accessToken !== null;
}

let onAuthFailure: () => void = () => {};

/** Called (once per failure) when the session cannot be recovered; the app routes to /login. */
export function setAuthFailureHandler(fn: () => void): void {
  onAuthFailure = fn;
}

async function parseBody(res: Response): Promise<unknown> {
  return res.status === 204 ? undefined : await res.json().catch(() => undefined);
}

function toApiError(res: Response, body: unknown): ApiError {
  const err = (body as ApiErrorBody | undefined)?.error;
  return new ApiError(res.status, err?.code ?? 'HTTP_ERROR', err?.message ?? res.statusText, err?.details);
}

/**
 * Rotates the refresh token. Rotation invalidates the old token and reusing it
 * revokes the whole session, so all callers share one in-flight request.
 * Resolves true on success, false when the refresh token is missing/rejected
 * (tokens are cleared). Network errors reject and leave the tokens alone.
 */
let refreshInFlight: Promise<boolean> | null = null;

export function refreshSession(): Promise<boolean> {
  refreshInFlight ??= doRefresh().finally(() => {
    refreshInFlight = null;
  });
  return refreshInFlight;
}

async function doRefresh(): Promise<boolean> {
  const refreshToken = readRefreshToken();
  if (!refreshToken) {
    clearTokens();
    return false;
  }
  const res = await fetch(API_BASE_URL + '/v1/auth/refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...TUNNEL_HEADERS },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!res.ok) {
    if (res.status >= 500) throw toApiError(res, await parseBody(res));
    clearTokens();
    return false;
  }
  setTokens((await res.json()) as TokenPair);
  return true;
}

/** True when an access token is available, refreshing first if only a refresh token is stored. */
export async function ensureSession(): Promise<boolean> {
  if (accessToken) return true;
  if (!readRefreshToken()) return false;
  return refreshSession();
}

/** Current access token (for the WebSocket handshake); null when signed out. */
export function getAccessToken(): string | null {
  return accessToken;
}

/**
 * Authenticated fetch; REST lives under /v1 except system routes like /health.
 * Retries once after a token refresh on 401 and throws ApiError on any non-2xx.
 */
export async function apiRaw(path: string, init?: RequestInit): Promise<Response> {
  const send = (token: string | null) =>
    fetch(API_BASE_URL + path, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        ...TUNNEL_HEADERS,
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init?.headers,
      },
    });

  const usedToken = accessToken;
  let res = await send(usedToken);

  if (res.status === 401 && readRefreshToken()) {
    // Another request may already have rotated the tokens while this one was in flight.
    const ok = accessToken && accessToken !== usedToken ? true : await refreshSession();
    if (ok) {
      res = await send(accessToken);
    } else {
      onAuthFailure();
    }
  } else if (res.status === 401 && usedToken) {
    clearTokens();
    onAuthFailure();
  }

  if (!res.ok) throw toApiError(res, await parseBody(res));
  return res;
}

/** JSON API call (see apiRaw). */
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await apiRaw(path, init);
  return (await parseBody(res)) as T;
}

export function postJson<T>(path: string, body?: unknown): Promise<T> {
  return api<T>(path, { method: 'POST', body: JSON.stringify(body ?? {}) });
}

export function patchJson<T>(path: string, body?: unknown): Promise<T> {
  return api<T>(path, { method: 'PATCH', body: JSON.stringify(body ?? {}) });
}

/** Builds `?a=1&b=2`, skipping empty/undefined values; returns '' when nothing is set. */
export function qs(params: Record<string, string | number | boolean | undefined | null>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : '';
}

/** Fetches a file with the auth header and hands it to the browser as a download. */
export async function downloadFile(path: string, fallbackName: string): Promise<void> {
  const res = await apiRaw(path);
  const blob = await res.blob();
  const name = res.headers.get('Content-Disposition')?.match(/filename="?([^";]+)"?/)?.[1] ?? fallbackName;
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

// ---------------------------------------------------------------------------
// Auth endpoints (SPEC §7.1)
// ---------------------------------------------------------------------------

export async function adminLogin(email: string, password: string): Promise<void> {
  const res = await fetch(API_BASE_URL + '/v1/auth/admin/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...TUNNEL_HEADERS },
    body: JSON.stringify({ email, password }),
  });
  const body = await parseBody(res);
  if (!res.ok) throw toApiError(res, body);
  setTokens(body as TokenPair);
}

/**
 * Changes the signed-in admin's password. The server signs out every other admin
 * session and returns a fresh token pair for this one, which replaces the stored tokens.
 */
export async function changeAdminPassword(currentPassword: string, newPassword: string): Promise<void> {
  const tokens = await postJson<TokenPair>('/v1/admin/settings/password', {
    current_password: currentPassword,
    new_password: newPassword,
  });
  setTokens(tokens);
}

export async function logout(): Promise<void> {
  try {
    if (await ensureSession()) await api<void>('/v1/auth/logout', { method: 'POST' });
  } finally {
    clearTokens();
  }
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

export interface Health {
  status: 'ok' | 'error';
  db: boolean;
  redis: boolean;
  osrm: boolean;
}

// /health returns 503 with the same body when degraded, so read it either way.
export async function getHealth(): Promise<Health> {
  const res = await fetch(API_BASE_URL + '/health', { headers: TUNNEL_HEADERS });
  return (await res.json()) as Health;
}
