import { Inject, Injectable } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { PrismaService } from '../../common/prisma.service';
import { RedisService } from '../../common/redis.service';

export interface HealthReport {
  status: 'ok' | 'error';
  db: boolean;
  redis: boolean;
  osrm: boolean;
}

const CHECK_TIMEOUT_MS = 2000;
// Connaught Place — any point inside the NCR extract works.
const OSRM_PROBE = '/nearest/v1/driving/77.2167,28.6315';

function withTimeout<T>(p: Promise<T>): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error('timeout')), CHECK_TIMEOUT_MS).unref(),
    ),
  ]);
}

@Injectable()
export class HealthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  async check(): Promise<HealthReport> {
    const [db, redis, osrm] = await Promise.all([
      this.probe(() => this.prisma.$queryRaw`SELECT 1`),
      this.probe(async () => {
        if ((await this.redis.ping()) !== 'PONG') throw new Error('bad ping');
      }),
      this.probe(async () => {
        const res = await fetch(this.config.OSRM_BASE_URL + OSRM_PROBE);
        if (!res.ok) throw new Error(`osrm ${res.status}`);
      }),
    ]);
    // OSRM is not fatal: routing falls back to Google Directions (SPEC §9.2).
    return { status: db && redis ? 'ok' : 'error', db, redis, osrm };
  }

  private async probe(fn: () => Promise<unknown>): Promise<boolean> {
    try {
      await withTimeout(fn());
      return true;
    } catch {
      return false;
    }
  }
}
