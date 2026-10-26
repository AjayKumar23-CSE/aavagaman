import { JwtService } from '@nestjs/jwt';
import type { Env } from '../../config/env.schema';
import type { PrismaService } from '../../common/prisma.service';
import { TokenService } from './token.service';

interface Row {
  id: string;
  userId: string;
  tokenHash: string;
  expiresAt: Date;
  revokedAt: Date | null;
  device: unknown;
}

/** Minimal in-memory stand-in for prisma.refreshToken. */
function fakePrisma(status: 'active' | 'blocked' = 'active') {
  const rows: Row[] = [];
  const user = { id: 'u1', role: 'rider', status };
  const prisma = {
    refreshToken: {
      create: jest.fn(async ({ data }) => {
        const row = { id: `t${rows.length}`, revokedAt: null, device: null, ...data };
        rows.push(row);
        return row;
      }),
      findUnique: jest.fn(async ({ where }) => {
        const r = rows.find((x) => x.tokenHash === where.tokenHash);
        return r ? { ...r, user } : null;
      }),
      updateMany: jest.fn(async ({ where, data }) => {
        const hit = rows.filter(
          (r) =>
            (!where.id || r.id === where.id) &&
            (!where.userId || r.userId === where.userId) &&
            r.revokedAt === null,
        );
        hit.forEach((r) => Object.assign(r, data));
        return { count: hit.length };
      }),
    },
  };
  return { prisma: prisma as unknown as PrismaService, rows };
}

const config = { JWT_ACCESS_TTL: '15m', JWT_REFRESH_TTL: '90d', JWT_REFRESH_SECRET: 's' } as Env;
const jwt = new JwtService({ secret: 'a' });

describe('TokenService', () => {
  it('issues a JWT access token and stores only a hash of the refresh token', async () => {
    const { prisma, rows } = fakePrisma();
    const svc = new TokenService(jwt, prisma, config);
    const pair = await svc.issue({ id: 'u1', role: 'rider' });

    const claims = await jwt.verifyAsync(pair.access_token);
    expect(claims).toMatchObject({ sub: 'u1', role: 'rider', typ: 'access' });
    expect(claims.exp - claims.iat).toBe(15 * 60);
    expect(rows[0].tokenHash).toBe(svc.hashRefresh(pair.refresh_token));
    expect(rows[0].tokenHash).not.toBe(pair.refresh_token);
  });

  it('rotates: the old refresh token is revoked and a new pair returned', async () => {
    const { prisma, rows } = fakePrisma();
    const svc = new TokenService(jwt, prisma, config);
    const first = await svc.issue({ id: 'u1', role: 'rider' });
    const second = await svc.rotate(first.refresh_token);

    expect(second.refresh_token).not.toBe(first.refresh_token);
    expect(rows[0].revokedAt).not.toBeNull();
    expect(rows[1].revokedAt).toBeNull();
  });

  it('detects reuse and revokes every token of the user', async () => {
    const { prisma, rows } = fakePrisma();
    const svc = new TokenService(jwt, prisma, config);
    const first = await svc.issue({ id: 'u1', role: 'rider' });
    const second = await svc.rotate(first.refresh_token);

    await expect(svc.rotate(first.refresh_token)).rejects.toMatchObject({ code: 'REFRESH_REUSED' });
    expect(rows.every((r) => r.revokedAt !== null)).toBe(true);
    await expect(svc.rotate(second.refresh_token)).rejects.toMatchObject({
      code: 'REFRESH_REUSED',
    });
  });

  it('rejects unknown and expired tokens, and blocked users', async () => {
    const { prisma, rows } = fakePrisma();
    const svc = new TokenService(jwt, prisma, config);
    await expect(svc.rotate('nope-nope-nope')).rejects.toMatchObject({ code: 'REFRESH_INVALID' });

    const pair = await svc.issue({ id: 'u1', role: 'rider' });
    rows[0].expiresAt = new Date(Date.now() - 1000);
    await expect(svc.rotate(pair.refresh_token)).rejects.toMatchObject({ code: 'REFRESH_INVALID' });

    const blocked = fakePrisma('blocked');
    const svc2 = new TokenService(jwt, blocked.prisma, config);
    const p2 = await svc2.issue({ id: 'u1', role: 'rider' });
    await expect(svc2.rotate(p2.refresh_token)).rejects.toMatchObject({ code: 'USER_BLOCKED' });
  });
});
