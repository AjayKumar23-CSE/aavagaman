import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createBrowserRouter, redirect, RouterProvider, type LoaderFunctionArgs } from 'react-router';
import App from './App';
import Toaster from './components/Toaster';
import { ApiError, ensureSession, setAuthFailureHandler } from './lib/api';
import Dashboard from './pages/Dashboard';
import Login from './pages/Login';
import LiveMap from './pages/LiveMap';
import DriversList from './pages/drivers/DriversList';
import DriverDetail from './pages/drivers/DriverDetail';
import RidesList from './pages/rides/RidesList';
import RideDetail from './pages/rides/RideDetail';
import Riders from './pages/Riders';
import FareConfigPage from './pages/FareConfig';
import ServiceAreas from './pages/ServiceAreas';
import Reports from './pages/Reports';
import Settlements from './pages/Settlements';
import Sos from './pages/Sos';
import Audit from './pages/Audit';
import Settings from './pages/Settings';
import 'leaflet/dist/leaflet.css';
import '@geoman-io/leaflet-geoman-free/dist/leaflet-geoman.css';
import './index.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Never retry auth/validation/not-found failures; retry transient ones once.
      retry: (count, err) => !(err instanceof ApiError && err.status < 500) && count < 1,
    },
  },
});

async function safeEnsureSession(): Promise<boolean> {
  try {
    return await ensureSession();
  } catch {
    return false;
  }
}

/** Route guard: everything except /login needs a session (refreshing first if only a refresh token is stored). */
async function requireAuth({ request }: LoaderFunctionArgs) {
  if (await safeEnsureSession()) return null;
  const url = new URL(request.url);
  const next = url.pathname + url.search;
  return redirect(next === '/' ? '/login' : `/login?next=${encodeURIComponent(next)}`);
}

async function redirectIfAuthed() {
  return (await safeEnsureSession()) ? redirect('/') : null;
}

const router = createBrowserRouter([
  { path: '/login', element: <Login />, loader: redirectIfAuthed },
  {
    path: '/',
    element: <App />,
    loader: requireAuth,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'live', element: <LiveMap /> },
      { path: 'rides', element: <RidesList /> },
      { path: 'rides/:id', element: <RideDetail /> },
      { path: 'drivers', element: <DriversList /> },
      { path: 'drivers/:id', element: <DriverDetail /> },
      { path: 'riders', element: <Riders /> },
      { path: 'fare-config', element: <FareConfigPage /> },
      { path: 'service-areas', element: <ServiceAreas /> },
      { path: 'reports', element: <Reports /> },
      { path: 'settlements', element: <Settlements /> },
      { path: 'sos', element: <Sos /> },
      { path: 'audit', element: <Audit /> },
      { path: 'settings', element: <Settings /> },
    ],
  },
]);

setAuthFailureHandler(() => {
  queryClient.clear();
  const { pathname, search } = window.location;
  if (pathname !== '/login')
    void router.navigate(`/login?next=${encodeURIComponent(pathname + search)}`, { replace: true });
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
      <Toaster onNavigate={(to) => void router.navigate(to)} />
    </QueryClientProvider>
  </StrictMode>,
);
