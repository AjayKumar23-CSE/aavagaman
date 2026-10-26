import { checkLicenceNumber, normaliseLicenceNo } from './licence-number';

const NOW = new Date('2026-10-11T10:00:00Z');
const born = (y: number) => new Date(`${y}-06-15T00:00:00Z`);

describe('checkLicenceNumber', () => {
  it('reads a standard Delhi licence with no warnings', () => {
    expect(checkLicenceNumber('DL0420110012345', born(1990), NOW)).toEqual({
      standard: true,
      state_code: 'DL',
      state: 'Delhi',
      rto_code: '04',
      issue_year: 2011,
      warnings: [],
    });
  });

  it('ignores spaces, hyphens, slashes and case', () => {
    expect(normaliseLicenceNo('hr-26 2015/0001234')).toBe('HR2620150001234');
    expect(checkLicenceNumber('hr-26 2015/0001234', null, NOW)?.warnings).toEqual([]);
  });

  it('accepts renamed state codes still in circulation', () => {
    expect(checkLicenceNumber('TS0920180001234', null, NOW)?.state).toBe('Telangana');
    expect(checkLicenceNumber('UA0720090001234', null, NOW)?.state).toBe('Uttarakhand');
  });

  it('flags a non-standard layout without guessing its parts', () => {
    const c = checkLicenceNumber('P03072005123456', born(1985), NOW)!;
    expect(c.standard).toBe(false);
    expect(c.state_code).toBeNull();
    expect(c.warnings).toHaveLength(1);
    expect(c.warnings[0]).toMatch(/standard 15-character format/);
  });

  it('flags an unknown state, RTO 00 and impossible years', () => {
    expect(checkLicenceNumber('XX0420110012345', null, NOW)?.warnings).toEqual([
      'Unknown state code "XX".',
    ]);
    expect(checkLicenceNumber('DL0020110012345', null, NOW)?.warnings).toEqual([
      'RTO code 00 does not exist.',
    ]);
    expect(checkLicenceNumber('DL0420310012345', null, NOW)?.warnings).toEqual([
      'Year of issue 2031 is in the future.',
    ]);
    expect(checkLicenceNumber('DL0418900012345', null, NOW)?.warnings).toEqual([
      'Year of issue 1890 looks wrong.',
    ]);
  });

  it('flags a licence issued before the driver turned 16', () => {
    expect(checkLicenceNumber('DL0420050012345', born(1995), NOW)?.warnings).toEqual([
      'Issued in 2005, when the driver was under 16 (born 1995).',
    ]);
    // 16 in the year of issue is fine (two-wheeler licence).
    expect(checkLicenceNumber('DL0420110012345', born(1995), NOW)?.warnings).toEqual([]);
  });

  it('returns null without a licence number', () => {
    expect(checkLicenceNumber(null, null, NOW)).toBeNull();
  });
});
