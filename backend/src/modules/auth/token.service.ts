import { createHmac, randomBytes } from 'node:crypto';
import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Prisma, User } from '@prisma/client';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { parseDurationMs } from '../../common/duration';
import { PrismaService } from '../../common/prisma.service';

export interface TokenPair {
  access_token: string;
  refresh_token: string;
}

const refreshError = (code: string, message: string) =>
  new AppException(code, message, HttpStatus.UNAUTHORIZED);

/**
 * Access tokens: short-lived JWTs. Refresh tokens: opaque random strings, stored
 * only as an HMAC, rotated on every use; presenting a used token revokes the
 * whole family for that user (SPEC §16 reuse detection).
 */
@Injectable()
export class TokenService {
  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  hashRefresh(token: string): string {
    return createHmac('sha256', this.config.JWT_REFRESH_SECRET).update(token).digest('hex');
  }

  async issue(
    user: Pick<User, 'id' | 'role'>,
    device?: Prisma.InputJsonValue | null,
  ): Promise<TokenPair> {
    const access_token = await this.jwt.signAsync(
      { sub: user.id, role: user.role, typ: 'access' },
      { expiresIn: Math.floor(parseDurationMs(this.config.JWT_ACCESS_TTL) / 1000) },
    );
    const refresh_token = randomBytes(32).toString('base64url');
    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: this.hashRefresh(refresh_token),
        expiresAt: new Date(Date.now() + parseDurationMs(this.config.JWT_REFRESH_TTL)),
        device: device ?? undefined,
      },
    });
    return { access_token, refresh_token };
  }

  async rotate(refreshToken: string): Promise<TokenPair> {
    const row = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: this.hashRefresh(refreshToken) },
      include: { user: true },
    });
    if (!row) throw refreshError('REFRESH_INVALID', 'Session expired. Please log in again.');

    if (row.revokedAt) {
      await this.revokeAll(row.userId);
      throw refreshError('REFRESH_REUSED', 'Session expired. Please log in again.');
    }
    if (row.expiresAt <= new Date()) {
      throw refreshError('REFRESH_INVALID', 'Session expired. Please log in again.');
    }
    if (row.user.status !== 'active') {
      await this.revokeAll(row.userId);
      throw new AppException('USER_BLOCKED', 'This account is blocked', HttpStatus.FORBIDDEN);
    }

    // Atomic claim: a concurrent rotation of the same token counts as reuse.
    const claimed = await this.prisma.refreshToken.updateMany({
      where: { id: row.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (claimed.count === 0) {
      await this.revokeAll(row.userId);
      throw refreshError('REFRESH_REUSED', 'Session expired. Please log in again.');
    }
    return this.issue(row.user, row.device as Prisma.InputJsonValue | null);
  }

  /**
   * Administrative sign-out (logout, password change, account block/delete): the tokens
   * simply disappear, so presenting one later is REFRESH_INVALID — not a reuse alarm that
   * would also kill the sessions created afterwards (D-045).
   */
  deleteAll(userId: string) {
    return this.prisma.refreshToken.deleteMany({ where: { userId } });
  }

  /** Reuse detection (SPEC §16): marks the whole family revoked; presenting any of them later is REFRESH_REUSED. */
  revokeAll(userId: string) {
    return this.prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }
}
