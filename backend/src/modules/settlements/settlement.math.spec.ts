import { istDayStart, istWeekStart, settlementTotals } from './settlement.math';

describe('settlement math (SPEC §15)', () => {
  const cfg = { gstPct: 5, commissionPct: 15 };

  it('splits gross, commission on the fare excluding GST, and cash vs online', () => {
    const t = settlementTotals([
      { finalFare: 210, paidWith: 'cash', amountPaid: 210, ...cfg },
      { finalFare: 210, paidWith: 'online', amountPaid: 240, ...cfg }, // + INR 30 carried fee
    ]);
    // gst per ride = 210 − 210/1.05 = 10; commission = (210 − 10) × 15% = 30
    expect(t).toEqual({
      rides_count: 2,
      gross_fares: 420,
      commission: 60,
      gst_on_gross: 20,
      cash_collected: 210,
      online_collected: 240,
      amount_payable: 160, // 240 − 60 − 20
    });
  });

  it('is negative when the driver kept more cash than their share', () => {
    const t = settlementTotals([{ finalFare: 100, paidWith: 'cash', amountPaid: 100, ...cfg }]);
    expect(t.amount_payable).toBeLessThan(0);
    expect(t.amount_payable).toBeCloseTo(-(t.commission + t.gst_on_gross), 2);
  });

  it('handles an empty period', () => {
    expect(settlementTotals([]).amount_payable).toBe(0);
  });

  it('IST day and week boundaries', () => {
    // 2026-09-30 is a Wednesday. 20:00 UTC on the 29th is 01:30 IST on the 30th.
    const at = new Date('2026-09-29T20:00:00Z');
    expect(istDayStart(at).toISOString()).toBe('2026-09-29T18:30:00.000Z'); // 30 Sep 00:00 IST
    expect(istWeekStart(at).toISOString()).toBe('2026-09-27T18:30:00.000Z'); // Mon 28 Sep 00:00 IST
    // A Monday maps to itself.
    expect(istWeekStart(new Date('2026-09-28T03:00:00Z')).toISOString()).toBe(
      '2026-09-27T18:30:00.000Z',
    );
  });
});
