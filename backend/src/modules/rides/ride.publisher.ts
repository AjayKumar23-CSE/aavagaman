import { Injectable } from '@nestjs/common';
import { PushMessage, PushService } from '../notifications/push.service';
import { RealtimeEmitter } from '../realtime/realtime.emitter';
import { rideStatusEvent } from './ride.presenter';
import type { LoadedRide } from './ride.repository';

const inr = (v: unknown) => `INR ${Number(v ?? 0).toFixed(0)}`;
const due = (r: LoadedRide) => Number(r.finalFare ?? 0) + Number(r.cancellationFee ?? 0);

/** Rider push per status (SPEC §14). */
function riderPush(r: LoadedRide): PushMessage | null {
  const d = r.driver?.user;
  switch (r.status) {
    case 'ACCEPTED':
      return {
        title: 'Driver assigned',
        body: `Driver ${d?.name ?? ''} is on the way (${r.vehicle?.regNumber ?? ''})`,
      };
    case 'ARRIVED':
      return {
        title: 'Your driver has arrived',
        body: `Your driver has arrived. OTP: ${r.tripOtp}`,
      };
    case 'STARTED':
      return { title: 'Trip started', body: 'Trip started' };
    case 'COMPLETED':
      return {
        title: 'Trip completed',
        body: `Trip completed. Fare ${inr(r.finalFare)}${Number(r.cancellationFee ?? 0) > 0 ? ` + ${inr(r.cancellationFee)} cancellation fee` : ''}`,
      };
    case 'PAID':
      return r.paymentMethod === 'online'
        ? { title: 'Payment received', body: 'Payment received' }
        : null;
    case 'CANCELLED': {
      const fee = Number(r.cancellationFee ?? 0);
      return {
        title: 'Ride cancelled',
        body: [
          r.cancelReason ?? 'Your ride was cancelled.',
          fee > 0 ? `Cancellation fee ${inr(fee)}.` : '',
        ]
          .filter(Boolean)
          .join(' '),
      };
    }
    case 'NO_DRIVER':
      return { title: 'No drivers available', body: 'No drivers available right now' };
    default:
      return null;
  }
}

/** Driver push per status (SPEC §14). */
function driverPush(r: LoadedRide): PushMessage | null {
  switch (r.status) {
    case 'COMPLETED':
      return { title: 'Trip completed', body: `Collect ${inr(due(r))}` };
    case 'PAID':
      return r.paymentMethod === 'online'
        ? { title: 'Rider paid online', body: 'Rider paid online' }
        : null;
    case 'CANCELLED':
      return r.cancelledBy === 'driver'
        ? null
        : { title: 'Ride cancelled', body: `Ride cancelled by ${r.cancelledBy ?? 'rider'}` };
    default:
      return null;
  }
}

/** Every transition: `ride:status` over WebSocket **and** an FCM push (SPEC §8, §10). */
@Injectable()
export class RidePublisher {
  constructor(
    private readonly rt: RealtimeEmitter,
    private readonly push: PushService,
  ) {}

  status(r: LoadedRide, opts: { previousDriverId?: string | null } = {}) {
    this.rt.toUser(r.riderId, 'ride:status', rideStatusEvent(r, 'rider'));
    if (r.driverId) this.rt.toUser(r.driverId, 'ride:status', rideStatusEvent(r, 'driver'));
    // A driver who just lost the ride (driver cancel re-queue, admin reassign) must hear about it too.
    const prev = opts.previousDriverId;
    if (prev && prev !== r.driverId)
      this.rt.toUser(prev, 'ride:status', { ride_id: r.id, status: 'CANCELLED', reassigned: true });
    this.rt.toAdmins('ride:status', rideStatusEvent(r, 'admin'));

    const data = { type: 'ride_status', ride_id: r.id, status: r.status };
    const rp = riderPush(r);
    if (rp) void this.push.toUser(r.riderId, { ...rp, data });
    const dp = r.driverId ? driverPush(r) : null;
    if (dp && r.driverId) void this.push.toUser(r.driverId, { ...dp, data });
  }

  /** Operational alerts for the admin panel (suspensions, OTP failures; SPEC §9.5, §9.6). */
  adminAlert(type: string, payload: Record<string, unknown>) {
    this.rt.toAdmins('admin:alert', { type, ...payload, at: new Date().toISOString() });
  }

  noDriver(r: LoadedRide) {
    this.rt.toUser(r.riderId, 'ride:no_driver', { ride_id: r.id });
    this.status(r);
  }
}
