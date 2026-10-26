import type { Feature, LineString } from 'geojson';
import { api, postJson, qs } from './api';
import type { Paginated } from './drivers';

export type RideStatus =
  | 'REQUESTED'
  | 'ACCEPTED'
  | 'ARRIVED'
  | 'STARTED'
  | 'COMPLETED'
  | 'PAID'
  | 'CANCELLED'
  | 'NO_DRIVER';

export const RIDE_STATUSES: RideStatus[] = [
  'REQUESTED',
  'ACCEPTED',
  'ARRIVED',
  'STARTED',
  'COMPLETED',
  'PAID',
  'CANCELLED',
  'NO_DRIVER',
];

export type PaymentMethod = 'cash' | 'online';

export interface Place {
  lat: number;
  lng: number;
  address: string;
}

export interface RideDriver {
  id: string;
  name: string | null;
  rating: number | null;
  phone: string;
  phone_masked: string;
  vehicle: { reg_number: string; make: string; model: string; colour: string } | null;
}

export interface RideRider {
  id: string;
  name: string | null;
  rating: number | null;
  phone: string;
  phone_masked: string;
}

export interface Ride {
  id: string;
  status: RideStatus;
  vehicle_type: string;
  payment_method: PaymentMethod;
  pickup: Place;
  drop: Place;
  est_distance_m: number | null;
  est_duration_s: number | null;
  est_fare_min: number | null;
  est_fare_max: number | null;
  actual_distance_m: number | null;
  actual_duration_s: number | null;
  final_fare: number | null;
  cancellation_fee: number | null;
  amount_due: number | null;
  cancelled_by: 'rider' | 'driver' | 'admin' | 'system' | null;
  cancel_reason: string | null;
  fare_config_id: string;
  requested_at: string;
  accepted_at: string | null;
  arrived_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  paid_at: string | null;
  cancelled_at: string | null;
  trip_otp: string;
  share_token: string;
  otp_attempts: number;
  driver: RideDriver | null;
  rider: RideRider;
}

export interface RideEvent {
  id: number;
  from_status: RideStatus | null;
  to_status: RideStatus;
  actor: string;
  actor_id: string | null;
  meta: Record<string, unknown> | null;
  at: string;
}

export interface RideOffer {
  id: string;
  driver_id: string;
  driver_name: string | null;
  distance_to_pickup_m: number | null;
  offered_at: string;
  responded_at: string | null;
  response: 'accepted' | 'rejected' | 'timeout' | 'withdrawn' | null;
}

export interface Payment {
  id: string;
  ride_id: string;
  method: PaymentMethod;
  amount: number;
  status: 'created' | 'paid' | 'failed' | string;
  gateway_order_id: string | null;
  gateway_payment_id: string | null;
  paid_at: string | null;
  created_at: string;
}

/** A call bridged through the Aavagaman number (D-058). */
export interface RideCall {
  id: string;
  ride_id: string;
  caller_id: string;
  callee_id: string;
  provider: string;
  provider_call_id: string | null;
  status: 'initiated' | 'ringing' | 'in_progress' | 'completed' | 'no_answer' | 'busy' | 'failed';
  duration_s: number | null;
  failure_reason: string | null;
  via: string;
  created_at: string;
  ended_at: string | null;
}

export interface RideTrack extends Feature<LineString> {
  properties: { ride_id: string; points: number; from: string | null; to: string | null };
}

export interface RideDetail {
  ride: Ride;
  events: RideEvent[];
  offers: RideOffer[];
  payment: Payment | null;
  track: RideTrack;
  calls: RideCall[];
}

export interface RideListParams {
  status?: RideStatus;
  /** ISO instants: requested_at ≥ from, < to. */
  from?: string;
  to?: string;
  driver_id?: string;
  rider_id?: string;
  page: number;
  limit: number;
}

export function listRides(p: RideListParams): Promise<Paginated<Ride>> {
  return api(`/v1/admin/rides${qs({ ...p })}`);
}

export function getRide(id: string): Promise<RideDetail> {
  return api(`/v1/admin/rides/${encodeURIComponent(id)}`);
}

export type RideAction = 'cancel' | 'reassign' | 'adjust-fare' | 'mark-cash';

/** Which admin actions the backend accepts per status (SPEC §7.4, §10). */
export const RIDE_ACTIONS: { action: RideAction; label: string; from: RideStatus[]; destructive: boolean }[] = [
  { action: 'cancel', label: 'Cancel ride', from: ['REQUESTED', 'ACCEPTED', 'ARRIVED', 'STARTED'], destructive: true },
  { action: 'reassign', label: 'Reassign driver', from: ['ACCEPTED', 'ARRIVED'], destructive: true },
  { action: 'adjust-fare', label: 'Adjust fare', from: ['COMPLETED', 'PAID', 'CANCELLED'], destructive: true },
  { action: 'mark-cash', label: 'Mark cash collected', from: ['COMPLETED'], destructive: false },
];

export function cancelRide(id: string, reason: string): Promise<Ride> {
  return postJson(`/v1/admin/rides/${encodeURIComponent(id)}/cancel`, { reason });
}

export function reassignRide(id: string, driver_id: string): Promise<Ride> {
  return postJson(`/v1/admin/rides/${encodeURIComponent(id)}/reassign`, { driver_id });
}

export function adjustFare(id: string, final_fare: number, reason: string): Promise<Ride> {
  return postJson(`/v1/admin/rides/${encodeURIComponent(id)}/adjust-fare`, { final_fare, reason });
}

export function markCash(id: string): Promise<Ride> {
  return postJson(`/v1/admin/rides/${encodeURIComponent(id)}/mark-cash`);
}
