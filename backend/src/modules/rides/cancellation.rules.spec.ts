import { cancellationOutcome, CancellationRules } from './cancellation.rules';

const rules: CancellationRules = { cancellationFee: 30, freeCancelWindowS: 120, noShowWaitS: 300 };
const T = Date.parse('2026-09-28T10:00:00Z');
const at = (s: number) => new Date(T + s * 1000);

describe('cancellation rules (SPEC §9.5)', () => {
  it('rider cancels in REQUESTED: no fee', () => {
    expect(
      cancellationOutcome(
        { status: 'REQUESTED', acceptedAt: null, arrivedAt: null },
        'rider',
        at(0),
        rules,
      ),
    ).toEqual({
      to: 'CANCELLED',
      fee: 0,
      countsAgainstDriver: false,
      noShow: false,
    });
  });

  it('rider cancels within 120 s of acceptance: no fee; later: fee', () => {
    const ride = { status: 'ACCEPTED' as const, acceptedAt: at(0), arrivedAt: null };
    expect(cancellationOutcome(ride, 'rider', at(120), rules).fee).toBe(0);
    expect(cancellationOutcome(ride, 'rider', at(121), rules).fee).toBe(30);
  });

  it('rider cancels after ARRIVED: fee', () => {
    const o = cancellationOutcome(
      { status: 'ARRIVED', acceptedAt: at(0), arrivedAt: at(200) },
      'rider',
      at(201),
      rules,
    );
    expect(o).toMatchObject({ to: 'CANCELLED', fee: 30, countsAgainstDriver: false });
  });

  it('driver cancels after ACCEPTED: no fee to rider, counts against driver, ride re-queued', () => {
    const o = cancellationOutcome(
      { status: 'ACCEPTED', acceptedAt: at(0), arrivedAt: null },
      'driver',
      at(60),
      rules,
    );
    expect(o).toEqual({ to: 'REQUESTED', fee: 0, countsAgainstDriver: true, noShow: false });
  });

  it('driver cancels before waiting 300 s at pickup: still counts, re-queued', () => {
    const o = cancellationOutcome(
      { status: 'ARRIVED', acceptedAt: at(0), arrivedAt: at(100) },
      'driver',
      at(399),
      rules,
    );
    expect(o).toMatchObject({ to: 'REQUESTED', fee: 0, countsAgainstDriver: true });
  });

  it('rider no-show: driver cancels 300 s after arriving: fee to rider, not counted', () => {
    const o = cancellationOutcome(
      { status: 'ARRIVED', acceptedAt: at(0), arrivedAt: at(100) },
      'driver',
      at(400),
      rules,
    );
    expect(o).toEqual({ to: 'CANCELLED', fee: 30, countsAgainstDriver: false, noShow: true });
  });

  it('admin and system cancels never charge', () => {
    const ride = { status: 'ARRIVED' as const, acceptedAt: at(0), arrivedAt: at(100) };
    expect(cancellationOutcome(ride, 'admin', at(999), rules)).toMatchObject({
      to: 'CANCELLED',
      fee: 0,
    });
    expect(cancellationOutcome(ride, 'system', at(999), rules)).toMatchObject({
      to: 'CANCELLED',
      fee: 0,
    });
  });
});
