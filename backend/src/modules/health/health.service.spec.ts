import { HealthService } from './health.service';
import type { Env } from '../../config/env.schema';

describe('HealthService', () => {
  const config = { OSRM_BASE_URL: 'http://osrm:5000' } as Env;
  const okFetch = jest.fn().mockResolvedValue({ ok: true });

  function make(db: () => Promise<unknown>, ping: () => Promise<string>) {
    const prisma = { $queryRaw: jest.fn(db) } as never;
    const redis = { ping: jest.fn(ping) } as never;
    return new HealthService(prisma, redis, config);
  }

  beforeEach(() => {
    global.fetch = okFetch as unknown as typeof fetch;
  });

  it('reports ok when every dependency answers', async () => {
    const s = make(
      async () => [1],
      async () => 'PONG',
    );
    await expect(s.check()).resolves.toEqual({ status: 'ok', db: true, redis: true, osrm: true });
  });

  it('reports error when the database is down', async () => {
    const s = make(
      async () => Promise.reject(new Error('down')),
      async () => 'PONG',
    );
    await expect(s.check()).resolves.toMatchObject({ status: 'error', db: false });
  });

  it('stays ok when only OSRM is down', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue({ ok: false, status: 500 }) as unknown as typeof fetch;
    const s = make(
      async () => [1],
      async () => 'PONG',
    );
    await expect(s.check()).resolves.toEqual({ status: 'ok', db: true, redis: true, osrm: false });
  });
});
