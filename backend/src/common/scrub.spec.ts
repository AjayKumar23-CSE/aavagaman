import { scrub } from './scrub';

describe('scrub', () => {
  it('redacts phone and token fields at any depth', () => {
    expect(
      scrub({
        phone: '+919812345678',
        user: { name: 'A', refresh_token: 'x', devices: [{ fcm_token: 'y', platform: 'android' }] },
        headers: { Authorization: 'Bearer z' },
      }),
    ).toEqual({
      phone: '[redacted]',
      user: {
        name: 'A',
        refresh_token: '[redacted]',
        devices: [{ fcm_token: '[redacted]', platform: 'android' }],
      },
      headers: { Authorization: '[redacted]' },
    });
  });
});
