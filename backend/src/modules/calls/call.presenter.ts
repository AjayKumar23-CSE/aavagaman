import type { RideCall } from '@prisma/client';

export function presentCall(c: RideCall, via: string) {
  return {
    id: c.id,
    ride_id: c.rideId,
    caller_id: c.callerId,
    callee_id: c.calleeId,
    provider: c.provider,
    provider_call_id: c.providerCallId,
    status: c.status,
    duration_s: c.durationS,
    failure_reason: c.failureReason,
    via,
    created_at: c.createdAt,
    ended_at: c.endedAt,
  };
}
