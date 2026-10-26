import { timingSafeEqual } from 'node:crypto';
import {
  Controller,
  Get,
  Headers,
  HttpStatus,
  Inject,
  NotFoundException,
  Query,
  Res,
} from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response } from 'express';
import { AppException } from '../../common/app.exception';
import { Public } from '../../common/auth/decorators';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { istDayStart } from '../settlements/settlement.math';

const same = (a: string, b: string) =>
  a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

/** SPEC §7.5: Prometheus text with basic counters/gauges, protected by METRICS_TOKEN. */
@ApiExcludeController()
@Public()
@Controller('metrics')
export class MetricsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  @Get()
  async metrics(
    @Headers('authorization') auth = '',
    @Query('token') token = '',
    @Res() res: Response,
  ) {
    const expected = this.config.METRICS_TOKEN;
    if (!expected) throw new NotFoundException();
    const given = auth.startsWith('Bearer ') ? auth.slice(7) : token;
    if (!same(given, expected))
      throw new AppException('UNAUTHORIZED', 'Bad metrics token', HttpStatus.UNAUTHORIZED);

    const dayStart = istDayStart(new Date());
    const [byStatus, online, states, pendingPayments, openSos, offers] = await Promise.all([
      this.prisma.ride.groupBy({
        by: ['status'],
        where: { requestedAt: { gte: dayStart } },
        _count: true,
      }),
      this.redis.zcard(K.geo),
      this.prisma.$queryRaw<
        { n: bigint }[]
      >`SELECT count(*) AS n FROM rides WHERE status IN ('ACCEPTED','ARRIVED','STARTED')`,
      this.prisma.payment.count({ where: { status: 'pending', gatewayOrderId: { not: null } } }),
      this.prisma.sosAlert.count({ where: { acknowledgedAt: null } }),
      this.prisma.rideOffer.groupBy({
        by: ['response'],
        where: { offeredAt: { gte: dayStart } },
        _count: true,
      }),
    ]);

    const lines: string[] = [
      '# HELP ride_requests_today Rides requested since IST midnight, by current status',
      '# TYPE ride_requests_today gauge',
      ...byStatus.map((s) => `ride_requests_today{status="${s.status}"} ${s._count}`),
      '# HELP ride_offers_today Offers made since IST midnight, by response',
      '# TYPE ride_offers_today gauge',
      ...offers.map((o) => `ride_offers_today{response="${o.response ?? 'pending'}"} ${o._count}`),
      '# HELP drivers_online Drivers currently in the GEO set',
      '# TYPE drivers_online gauge',
      `drivers_online ${online}`,
      '# HELP rides_active Rides currently ACCEPTED, ARRIVED or STARTED',
      '# TYPE rides_active gauge',
      `rides_active ${Number(states[0]?.n ?? 0)}`,
      '# HELP payments_pending_online Online payments awaiting capture',
      '# TYPE payments_pending_online gauge',
      `payments_pending_online ${pendingPayments}`,
      '# HELP sos_open Unacknowledged SOS alerts',
      '# TYPE sos_open gauge',
      `sos_open ${openSos}`,
      '# HELP process_uptime_seconds API process uptime',
      '# TYPE process_uptime_seconds gauge',
      `process_uptime_seconds ${Math.round(process.uptime())}`,
    ];
    res.type('text/plain; version=0.0.4; charset=utf-8').send(lines.join('\n') + '\n');
  }
}
