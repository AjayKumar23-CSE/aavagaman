import { createHmac } from 'node:crypto';
import { verifyCheckoutSignature, verifyWebhookSignature } from './razorpay.client';

describe('Razorpay signatures (SPEC §15)', () => {
  it('accepts the documented checkout signature and rejects tampering', () => {
    const sig = createHmac('sha256', 'secret').update('order_1|pay_1').digest('hex');
    expect(verifyCheckoutSignature('secret', 'order_1', 'pay_1', sig)).toBe(true);
    expect(verifyCheckoutSignature('secret', 'order_1', 'pay_2', sig)).toBe(false);
    expect(verifyCheckoutSignature('other', 'order_1', 'pay_1', sig)).toBe(false);
    expect(verifyCheckoutSignature('secret', 'order_1', 'pay_1', 'zz')).toBe(false);
    expect(verifyCheckoutSignature('secret', 'order_1', 'pay_1', '')).toBe(false);
  });

  it('verifies webhook signatures over the raw body bytes', () => {
    const body = Buffer.from('{"event":"payment.captured","payload":{}}');
    const sig = createHmac('sha256', 'whsec').update(body).digest('hex');
    expect(verifyWebhookSignature('whsec', body, sig)).toBe(true);
    expect(
      verifyWebhookSignature(
        'whsec',
        Buffer.from('{"event":"payment.captured","payload":{} }'),
        sig,
      ),
    ).toBe(false);
  });
});
