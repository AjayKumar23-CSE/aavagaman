import { otpMatches } from './trip.service';

describe('otpMatches', () => {
  it('matches only the exact 4-digit code', () => {
    expect(otpMatches('4821', '4821')).toBe(true);
    expect(otpMatches('4822', '4821')).toBe(false);
    expect(otpMatches('482', '4821')).toBe(false);
    expect(otpMatches('48210', '4821')).toBe(false);
    expect(otpMatches('', '4821')).toBe(false);
  });
});
