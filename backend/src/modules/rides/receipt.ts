import type { FareConfig } from '@prisma/client';
import { breakdown, estimate, FareConfigValues, gstOf } from '../fare/fare.engine';
import { toFareValues } from '../fare/fare.service';
import type { LoadedRide } from './ride.repository';

const r2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Fare breakdown for a COMPLETED/PAID ride (SPEC §7.2 receipt, §9.3 GST rules).
 * Recomputes the components from the stored actuals and the ride's fare config, so the
 * numbers always reconcile with `final_fare`.
 */
export function buildReceipt(ride: LoadedRide, cfg: FareConfig) {
  const values: FareConfigValues = toFareValues(cfg);
  const startedAt = ride.startedAt ?? ride.requestedAt ?? new Date();
  const actual = breakdown(ride.actualDistanceM ?? 0, ride.actualDurationS ?? 0, values, startedAt);
  const est = estimate(
    ride.estDistanceM ?? 0,
    ride.estDurationS ?? 0,
    values,
    ride.requestedAt ?? startedAt,
  );
  const cap = est.fare * 1.25;
  const fare = Number(ride.finalFare ?? 0);
  const gst = gstOf(fare, values.gstPct);
  const cancellationFee = Number(ride.cancellationFee ?? 0);
  return {
    ride_id: ride.id,
    status: ride.status,
    currency: 'INR' as const,
    distance_m: ride.actualDistanceM,
    duration_s: ride.actualDurationS,
    components: {
      base_fare: r2(actual.base),
      distance: r2(actual.distance),
      time: r2(actual.time),
      night_multiplier: actual.night_multiplier,
      raw: r2(actual.raw),
      min_fare_applied: actual.raw < values.minFare,
      cap_applied: !ride.dropAddress ? false : Math.max(values.minFare, actual.raw) > cap,
      cap: r2(cap),
    },
    fare,
    gst,
    fare_excl_gst: r2(fare - gst),
    cancellation_fee: cancellationFee,
    total: r2(fare + cancellationFee),
    payment_method: ride.paymentMethod,
    fare_config: {
      base_fare: values.baseFare,
      per_km: values.perKm,
      per_min: values.perMin,
      min_fare: values.minFare,
      gst_pct: values.gstPct,
    },
  };
}
