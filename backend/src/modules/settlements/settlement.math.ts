import { commissionOf, gstOf } from '../fare/fare.engine';

export interface SettledRide {
  finalFare: number;
  gstPct: number;
  commissionPct: number;
  /** How the payment was actually taken. */
  paidWith: 'cash' | 'online';
  /** Amount the rider paid on this ride (fare + carried cancellation fees). */
  amountPaid: number;
}

export interface SettlementTotals {
  rides_count: number;
  gross_fares: number;
  commission: number;
  gst_on_gross: number;
  cash_collected: number;
  online_collected: number;
  /** positive: platform pays driver; negative: driver owes platform (SPEC §15). */
  amount_payable: number;
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/** SPEC §15 settlement arithmetic over a driver's PAID rides in a period. */
export function settlementTotals(rides: SettledRide[]): SettlementTotals {
  let gross = 0;
  let commission = 0;
  let gst = 0;
  let cash = 0;
  let online = 0;
  for (const r of rides) {
    gross += r.finalFare;
    commission += commissionOf(r.finalFare, { gstPct: r.gstPct, commissionPct: r.commissionPct });
    gst += gstOf(r.finalFare, r.gstPct);
    if (r.paidWith === 'cash') cash += r.amountPaid;
    else online += r.amountPaid;
  }
  return {
    rides_count: rides.length,
    gross_fares: r2(gross),
    commission: r2(commission),
    gst_on_gross: r2(gst),
    cash_collected: r2(cash),
    online_collected: r2(online),
    amount_payable: r2(online - commission - gst),
  };
}

const IST_MS = 5.5 * 3_600_000;

/** Start of the IST day containing `at`, as a UTC instant. */
export function istDayStart(at: Date): Date {
  const ist = new Date(at.getTime() + IST_MS);
  return new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate()) - IST_MS);
}

/** Monday 00:00 IST of the week containing `at`. */
export function istWeekStart(at: Date): Date {
  const day = istDayStart(at);
  const dow = new Date(day.getTime() + IST_MS).getUTCDay(); // 0 = Sunday
  const back = (dow + 6) % 7; // days since Monday
  return new Date(day.getTime() - back * 86_400_000);
}

/** Calendar date (YYYY-MM-DD) of an IST instant, for DATE columns. */
export function istDate(at: Date): Date {
  const ist = new Date(at.getTime() + IST_MS);
  return new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate()));
}
