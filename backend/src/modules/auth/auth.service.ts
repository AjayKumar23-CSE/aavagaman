import { HttpStatus, Injectable } from '@nestjs/common';
import type { User } from '@prisma/client';
import * as argon2 from 'argon2';
import { AppException } from '../../common/app.exception';
import { normalizeIndianPhone } from '../../common/phone';
import { PrismaService } from '../../common/prisma.service';
import { RedisService } from '../../common/redis.service';
import { presentUser } from '../users/user.presenter';
import { AdminLoginDto, OtpSendDto, OtpVerifyDto } from './dto/auth.dto';
import { OtpService } from './otp.service';
import { TokenService } from './token.service';

export const ADMIN_MAX_FAILURES = 10; // SPEC §7.1
export const ADMIN_LOCK_SECONDS = 15 * 60;

@Injectable()
export class AuthService {
  // Verified against for unknown emails, so they cost the same as a wrong password.
  private readonly dummyHash = argon2.hash('no-such-admin', { type: argon2.argon2id });

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly otp: OtpService,
    private readonly tokens: TokenService,
  ) {}

  private phoneOrThrow(raw: string): string {
    const phone = normalizeIndianPhone(raw);
    if (!phone) {
      throw new AppException(
        'INVALID_PHONE',
        'Enter a valid Indian mobile number',
        HttpStatus.BAD_REQUEST,
      );
    }
    return phone;
  }

  sendOtp(dto: OtpSendDto, ip: string) {
    return this.otp.send(this.phoneOrThrow(dto.phone), ip);
  }

  async verifyOtp(dto: OtpVerifyDto) {
    const phone = this.phoneOrThrow(dto.phone);
    await this.otp.verify(phone, dto.code);

    let user: User | null = await this.prisma.user.findUnique({ where: { phone } });
    if (!user) {
      // New riders are created on the spot; new drivers start as pending (SPEC §7.1).
      user = await this.prisma.user.create({
        data: {
          phone,
          role: dto.role,
          ...(dto.role === 'driver' ? { driver: { create: {} } } : {}),
        },
      });
    } else if (user.role !== dto.role) {
      throw new AppException(
        'ROLE_MISMATCH',
        `This number is registered as a ${user.role}. Use the ${user.role} app.`,
        HttpStatus.FORBIDDEN,
      );
    }
    if (user.status !== 'active') {
      throw new AppException('USER_BLOCKED', 'This account is blocked', HttpStatus.FORBIDDEN);
    }

    const fcmToken = dto.device?.fcm_token;
    if (fcmToken && fcmToken !== user.fcmToken) {
      user = await this.prisma.user.update({ where: { id: user.id }, data: { fcmToken } });
    }

    const device = dto.device
      ? { platform: dto.device.platform, app_version: dto.device.app_version ?? null }
      : null;
    return { ...(await this.tokens.issue(user, device)), user: presentUser(user) };
  }

  refresh(refreshToken: string) {
    return this.tokens.rotate(refreshToken);
  }

  async logout(userId: string) {
    await this.prisma.user.update({ where: { id: userId }, data: { fcmToken: null } });
    await this.tokens.deleteAll(userId);
  }

  /**
   * Admin password change (SPEC §13 Settings; D-044). Verifies the current password,
   * counts failures towards the login lockout, revokes every other session and
   * returns a fresh token pair so the current browser stays signed in.
   */
  async changeAdminPassword(adminId: string, currentPassword: string, newPassword: string) {
    const user = await this.prisma.user.findFirst({ where: { id: adminId, role: 'admin' } });
    if (!user?.passwordHash)
      throw new AppException('NOT_ADMIN', 'Not an admin account', HttpStatus.FORBIDDEN);
    const lockKey = `admin:lf:${(user.email ?? user.id).toLowerCase()}`;
    if (Number(await this.redis.get(lockKey)) >= ADMIN_MAX_FAILURES) {
      throw new AppException(
        'ACCOUNT_LOCKED',
        'Too many failed attempts. Try again in 15 minutes.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    if (!(await argon2.verify(user.passwordHash, currentPassword).catch(() => false))) {
      await this.redis.multi().incr(lockKey).expire(lockKey, ADMIN_LOCK_SECONDS, 'NX').exec();
      throw new AppException(
        'INVALID_CREDENTIALS',
        'Current password is wrong',
        HttpStatus.UNAUTHORIZED,
      );
    }
    if (await argon2.verify(user.passwordHash, newPassword).catch(() => false)) {
      throw new AppException(
        'PASSWORD_REUSED',
        'Choose a password you have not used before',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    await this.prisma.user.update({
      where: { id: adminId },
      data: { passwordHash: await argon2.hash(newPassword, { type: argon2.argon2id }) },
    });
    await this.redis.del(lockKey);
    await this.tokens.deleteAll(adminId);
    return this.tokens.issue(user, { platform: 'admin-web' });
  }

  async adminLogin(dto: AdminLoginDto) {
    const email = dto.email.trim().toLowerCase();
    const lockKey = `admin:lf:${email}`;
    if (Number(await this.redis.get(lockKey)) >= ADMIN_MAX_FAILURES) {
      throw new AppException(
        'ACCOUNT_LOCKED',
        'Too many failed attempts. Try again in 15 minutes.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const user = await this.prisma.user.findFirst({
      where: { role: 'admin', email: { equals: email, mode: 'insensitive' } },
    });
    const ok = await argon2
      .verify(user?.passwordHash ?? (await this.dummyHash), dto.password)
      .catch(() => false);
    if (!user || !ok) {
      await this.redis.multi().incr(lockKey).expire(lockKey, ADMIN_LOCK_SECONDS, 'NX').exec();
      throw new AppException(
        'INVALID_CREDENTIALS',
        'Wrong email or password',
        HttpStatus.UNAUTHORIZED,
      );
    }
    if (user.status !== 'active') {
      throw new AppException('USER_BLOCKED', 'This account is blocked', HttpStatus.FORBIDDEN);
    }
    await this.redis.del(lockKey);
    return this.tokens.issue(user, { platform: 'admin-web' });
  }
}
