import { api } from './api';
import type { RideStatus } from './rides';

export interface Dashboard {
  day_start: string;
  rides_by_status: Partial<Record<RideStatus, number>>;
  rides_total: number;
  completed: number;
  cancellations: number;
  online_drivers: number;
  revenue: number;
  paid_rides: number;
  pending_drivers: number;
  open_sos: number;
}

/** Today's counts in IST (SPEC §7.4). Polled every 30 s by the app shell. */
export function getDashboard(): Promise<Dashboard> {
  return api('/v1/admin/dashboard');
}

export type DriverLiveState = 'idle' | 'offered' | 'on_trip' | 'offline';

export interface LiveDriver {
  driver_id: string;
  name: string | null;
  reg_number: string | null;
  state: DriverLiveState;
  lat: number | null;
  lng: number | null;
  heading: number;
  updated_at: string | null;
}

export interface LivePlace {
  lat: number;
  lng: number;
  address: string;
}

export interface LiveRide {
  ride_id: string;
  status: RideStatus;
  rider_name: string | null;
  driver_id: string | null;
  driver_name: string | null;
  pickup: LivePlace;
  drop: LivePlace;
  requested_at: string;
  accepted_at: string | null;
}

export interface LiveSnapshot {
  at: string;
  drivers: LiveDriver[];
  rides: LiveRide[];
}

/** Snapshot of online drivers + active rides; `admin:live` streams the same shape. */
export function getLive(): Promise<LiveSnapshot> {
  return api('/v1/admin/live');
}

/** Great-circle distance in metres (for sorting candidate drivers by distance to a pickup). */
export function haversineM(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6_371_000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
