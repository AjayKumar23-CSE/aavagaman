import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import { HttpStatus, Inject, Injectable, Logger } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { maskPhone } from '../../common/phone';
import { RedisService } from '../../common/redis.service';
import { SmsService } from '../notifications/sms.service';

export const OTP_PHONE_LIMIT = 5; // per hour (SPEC §7.1)
export const OTP_IP_LIMIT = 3; // per minute

const invalid = () =>
  // Generic on purpose: never reveal whether a code exists, expired or was locked (SPEC §16).
  new AppException('OTP_INVALID', 'Invalid or expired code', HttpStatus.UNAUTHORIZED);

@Injectable()
export class OtpService {
  private readonly logger = new Logger(OtpService.name);

  constructor(
    private readonly redis: RedisService,
    private readonly sms: SmsService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  hash(phone: string, code: string): string {
    return createHash('sha256').update(`${this.config.OTP_PEPPER}:${phone}:${code}`).digest('hex');
  }

  private async hit(key: string, windowSeconds: number): Promise<number> {
    const [[, count]] = (await this.redis
      .multi()
      .incr(key)
      .expire(key, windowSeconds, 'NX')
      .exec()) as [[null, number], unknown];
    return count;
  }

  async send(phone: string, ip: string): Promise<{ sent: true; ttl: number }> {
    if (
      (await this.hit(`otp:rl:ip:${ip}`, 60)) > OTP_IP_LIMIT ||
      (await this.hit(`otp:rl:${phone}`, 3600)) > OTP_PHONE_LIMIT
    ) {
      throw new AppException(
        'OTP_RATE_LIMITED',
        'Too many code requests. Try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const ttl = this.config.OTP_TTL_SECONDS;
    const key = `otp:${phone}`;
    await this.redis
      .multi()
      .del(key)
      .hset(key, { code_hash: this.hash(phone, code), attempts: 0 })
      .expire(key, ttl)
      .exec();

    try {
      await this.sms.sendOtp(phone, code);
    } catch (err) {
      this.logger.error(`OTP SMS to ${maskPhone(phone)} failed: ${(err as Error).message}`);
      await this.redis.del(key);
      throw new AppException(
        'SMS_UNAVAILABLE',
        'Could not send the code. Try again.',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return { sent: true, ttl };
  }

  /** Throws OTP_INVALID unless the code matches; a code is single-use. */
  async verify(phone: string, code: string): Promise<void> {
    const key = `otp:${phone}`;
    const bypass = this.config.OTP_DEV_BYPASS_CODE;
    if (bypass && this.config.NODE_ENV !== 'production' && code === bypass) {
      await this.redis.del(key);
      return;
    }

    const stored = await this.redis.hgetall(key);
    if (!stored.code_hash) throw invalid();
    if (Number(stored.attempts) >= this.config.OTP_MAX_ATTEMPTS) {
      await this.redis.del(key);
      throw invalid();
    }

    const expected = Buffer.from(stored.code_hash, 'hex');
    const actual = Buffer.from(this.hash(phone, code), 'hex');
    if (!timingSafeEqual(expected, actual)) {
      const attempts = await this.redis.hincrby(key, 'attempts', 1);
      if (attempts >= this.config.OTP_MAX_ATTEMPTS) await this.redis.del(key);
      throw invalid();
    }
    await this.redis.del(key);
  }
}
