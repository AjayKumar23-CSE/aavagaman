import RedisMock from 'ioredis-mock';
import type { Env } from '../../config/env.schema';
import type { RedisService } from '../../common/redis.service';
import type { SmsService } from '../notifications/sms.service';
import { OtpService } from './otp.service';

const PHONE = '+919812345678';

function setup(overrides: Partial<Env> = {}) {
  const redis = new RedisMock() as unknown as RedisService;
  const sent: string[] = [];
  const sms = {
    sendOtp: jest.fn(async (_p: string, code: string) => void sent.push(code)),
  } as unknown as SmsService;
  const config = {
    NODE_ENV: 'test',
    OTP_TTL_SECONDS: 300,
    OTP_MAX_ATTEMPTS: 3,
    OTP_PEPPER: 'pepper',
    ...overrides,
  } as Env;
  return { otp: new OtpService(redis, sms, config), redis, sent, sms };
}

describe('OtpService', () => {
  afterEach(async () => {
    await new RedisMock().flushall();
  });

  it('sends a 6-digit code, stores only its hash, and verifies it once', async () => {
    const { otp, redis, sent } = setup();
    await expect(otp.send(PHONE, '1.1.1.1')).resolves.toEqual({ sent: true, ttl: 300 });
    const code = sent[0];
    expect(code).toMatch(/^\d{6}$/);

    const stored = await redis.hgetall(`otp:${PHONE}`);
    expect(stored.code_hash).toBe(otp.hash(PHONE, code));
    expect(JSON.stringify(stored)).not.toContain(code);

    await expect(otp.verify(PHONE, code)).resolves.toBeUndefined();
    await expect(otp.verify(PHONE, code)).rejects.toMatchObject({ code: 'OTP_INVALID' });
  });

  it('locks the code after OTP_MAX_ATTEMPTS wrong tries', async () => {
    const { otp, sent } = setup();
    await otp.send(PHONE, '1.1.1.1');
    const wrong = sent[0] === '000000' ? '111111' : '000000';
    for (let i = 0; i < 3; i++) {
      await expect(otp.verify(PHONE, wrong)).rejects.toMatchObject({ code: 'OTP_INVALID' });
    }
    // Even the right code is refused now.
    await expect(otp.verify(PHONE, sent[0])).rejects.toMatchObject({ code: 'OTP_INVALID' });
  });

  it('rejects the 6th send to one phone within an hour', async () => {
    const { otp } = setup();
    for (let i = 0; i < 5; i++) await otp.send(PHONE, `10.0.0.${i}`);
    await expect(otp.send(PHONE, '10.0.0.99')).rejects.toMatchObject({ code: 'OTP_RATE_LIMITED' });
  });

  it('rejects the 4th send from one IP within a minute', async () => {
    const { otp } = setup();
    for (let i = 0; i < 3; i++) await otp.send(`+91981234567${i}`, '2.2.2.2');
    await expect(otp.send('+919812345679', '2.2.2.2')).rejects.toMatchObject({
      code: 'OTP_RATE_LIMITED',
    });
  });

  it('accepts the dev bypass code outside production only', async () => {
    await expect(
      setup({ OTP_DEV_BYPASS_CODE: '123456' }).otp.verify(PHONE, '123456'),
    ).resolves.toBeUndefined();
    await expect(
      setup({ OTP_DEV_BYPASS_CODE: '123456', NODE_ENV: 'production' }).otp.verify(PHONE, '123456'),
    ).rejects.toMatchObject({ code: 'OTP_INVALID' });
  });

  it('drops the code and reports 503 when the SMS fails', async () => {
    const { otp, redis, sms } = setup();
    (sms.sendOtp as jest.Mock).mockRejectedValueOnce(new Error('msg91 down'));
    await expect(otp.send(PHONE, '1.1.1.1')).rejects.toMatchObject({ code: 'SMS_UNAVAILABLE' });
    expect(await redis.exists(`otp:${PHONE}`)).toBe(0);
  });
});
