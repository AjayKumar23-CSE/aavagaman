import type { RideStatus } from '@prisma/client';
import { maskPhone } from '../../common/phone';
import type { LoadedRide } from './ride.repository';

export type Viewer = 'rider' | 'driver' | 'admin';

const num = (d: unknown) => (d === null || d === undefined ? null : Number(d));

/** Phones are masked between rider and driver until ARRIVED (SPEC §16). */
const PHONE_VISIBLE: readonly RideStatus[] = ['ARRIVED', 'STARTED', 'COMPLETED'];
/** With masked calling (D-058) the apps may bridge a call while the trip is live. */
const CALL_VISIBLE: readonly RideStatus[] = ['ACCEPTED', 'ARRIVED', 'STARTED'];

export type CallingPolicy = { masked: false } | { masked: true; via: string };

/** Number the stub provider advertises when no ExoPhone is configured. */
export const STUB_CALLER_ID = '+911140000000';

let calling: CallingPolicy = { masked: false };

/** Set once at startup (API and worker alike, from RideCoreModule): masked → real numbers never leave the server, `call_via` is advertised. */
export function configureCalling(policy: CallingPolicy) {
  calling = policy;
}

export function callingPolicyFor(env: { CALL_PROVIDER: 'none' | 'stub' | 'exotel'; EXOTEL_CALLER_ID?: string }): CallingPolicy {
  if (env.CALL_PROVIDER === 'none') return { masked: false };
  return { masked: true, via: env.EXOTEL_CALLER_ID ?? STUB_CALLER_ID };
}

/** `phone` (dialer mode after ARRIVED) or `call_via` (bridge mode while live), never both. */
function phoneFields(viewer: Viewer, status: RideStatus, phone: string) {
  if (viewer === 'admin') return { phone };
  if (calling.masked) return CALL_VISIBLE.includes(status) ? { call_via: calling.via } : {};
  return PHONE_VISIBLE.includes(status) ? { phone } : {};
}
/** The rider sees the trip OTP once a driver is assigned (SPEC §9.6). */
const OTP_VISIBLE: readonly RideStatus[] = ['ACCEPTED', 'ARRIVED'];

export function presentDriverPublic(r: LoadedRide, viewer: Viewer) {
  if (!r.driver) return null;
  const u = r.driver.user;
  return {
    id: u.id,
    name: u.name,
    rating: num(u.ratingAvg),
    phone_masked: maskPhone(u.phone),
    ...phoneFields(viewer, r.status, u.phone),
    vehicle: r.vehicle
      ? {
          reg_number: r.vehicle.regNumber,
          make: r.vehicle.make,
          model: r.vehicle.model,
          colour: r.vehicle.colour,
        }
      : null,
  };
}

function presentRiderPublic(r: LoadedRide, viewer: Viewer) {
  const u = r.rider;
  return {
    id: u.id,
    name: u.name,
    rating: num(u.ratingAvg),
    phone_masked: maskPhone(u.phone),
    ...phoneFields(viewer, r.status, u.phone),
  };
}

export function presentRide(r: LoadedRide, viewer: Viewer) {
  return {
    id: r.id,
    status: r.status,
    vehicle_type: r.vehicleType,
    payment_method: r.paymentMethod,
    pickup: { lat: r.coords.pickup_lat, lng: r.coords.pickup_lng, address: r.pickupAddress },
    drop: { lat: r.coords.drop_lat, lng: r.coords.drop_lng, address: r.dropAddress },
    est_distance_m: r.estDistanceM,
    est_duration_s: r.estDurationS,
    est_fare_min: num(r.estFareMin),
    est_fare_max: num(r.estFareMax),
    actual_distance_m: r.actualDistanceM,
    actual_duration_s: r.actualDurationS,
    final_fare: num(r.finalFare),
    cancellation_fee: num(r.cancellationFee),
    /** What the rider pays on this ride: final fare plus carried-over cancellation fees. */
    amount_due: r.finalFare === null ? null : Number(r.finalFare) + Number(r.cancellationFee ?? 0),
    cancelled_by: r.cancelledBy,
    cancel_reason: r.cancelReason,
    fare_config_id: r.fareConfigId,
    requested_at: r.requestedAt,
    accepted_at: r.acceptedAt,
    arrived_at: r.arrivedAt,
    started_at: r.startedAt,
    completed_at: r.completedAt,
    paid_at: r.paidAt,
    cancelled_at: r.cancelledAt,
    ...(viewer === 'rider'
      ? {
          trip_otp: OTP_VISIBLE.includes(r.status) ? r.tripOtp : null,
          share_token: r.shareToken,
        }
      : {}),
    ...(viewer === 'admin'
      ? { trip_otp: r.tripOtp, share_token: r.shareToken, otp_attempts: r.otpAttempts }
      : {}),
    driver: presentDriverPublic(r, viewer),
    ...(viewer !== 'rider' ? { rider: presentRiderPublic(r, viewer) } : {}),
  };
}

/** `ride:status` WebSocket payload (SPEC §8). */
export function rideStatusEvent(r: LoadedRide, viewer: Viewer) {
  const d = presentDriverPublic(r, viewer);
  return {
    ride_id: r.id,
    status: r.status,
    ...(d ? { driver: { ...d, rating: d.rating } } : {}),
    ...(r.finalFare !== null
      ? {
          final_fare: num(r.finalFare),
          cancellation_fee: num(r.cancellationFee),
          amount_due: Number(r.finalFare) + Number(r.cancellationFee ?? 0),
        }
      : {}),
    ...(r.status === 'CANCELLED'
      ? {
          cancellation_fee: num(r.cancellationFee),
          cancelled_by: r.cancelledBy,
          cancel_reason: r.cancelReason,
        }
      : {}),
    ...(viewer === 'rider' && OTP_VISIBLE.includes(r.status) ? { trip_otp: r.tripOtp } : {}),
  };
}
