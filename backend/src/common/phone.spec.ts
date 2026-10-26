import { maskPhone, normalizeIndianPhone } from './phone';

describe('normalizeIndianPhone', () => {
  it.each([
    ['9812345678', '+919812345678'],
    ['09812345678', '+919812345678'],
    ['919812345678', '+919812345678'],
    ['+91 98123 45678', '+919812345678'],
    ['+91-6012345678', '+916012345678'],
  ])('%s → %s', (input, out) => expect(normalizeIndianPhone(input)).toBe(out));

  it.each(['12345', '+915812345678', '+14155550100', 'abc'])('rejects %s', (input) =>
    expect(normalizeIndianPhone(input)).toBeNull(),
  );
});

describe('maskPhone', () => {
  it('keeps only the last 4 digits', () => {
    expect(maskPhone('+919812345678')).toBe('******5678');
    expect(maskPhone(null)).toBeNull();
  });
});
