import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Roles } from '../../common/auth/decorators';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { istDayStart } from '../settlements/settlement.math';
import { LiveService } from './live.service';

@ApiTags('admin: dashboard')
@ApiBearerAuth()
@Roles('admin')
@Controller('admin')
export class AdminDashboardController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly live: LiveService,
  ) {}

  /** SPEC §7.4: today's (IST) counts. */
  @Get('dashboard')
  async dashboard() {
    const from = istDayStart(new Date());
    const [byStatus, onlineDrivers, revenue, cancellations, pendingDrivers, openSos] =
      await Promise.all([
        this.prisma.ride.groupBy({
          by: ['status'],
          where: { requestedAt: { gte: from } },
          _count: true,
        }),
        this.redis.zcard(K.geo),
        this.prisma.payment.aggregate({
          where: { status: 'paid', paidAt: { gte: from } },
          _sum: { amount: true },
          _count: true,
        }),
        this.prisma.ride.count({ where: { status: 'CANCELLED', cancelledAt: { gte: from } } }),
        this.prisma.driver.count({ where: { verificationStatus: 'pending' } }),
        this.prisma.sosAlert.count({ where: { acknowledgedAt: null } }),
      ]);
    const counts = Object.fromEntries(byStatus.map((s) => [s.status, s._count]));
    return {
      day_start: from,
      rides_by_status: counts,
      rides_total: byStatus.reduce((n, s) => n + s._count, 0),
      completed: (counts.COMPLETED ?? 0) + (counts.PAID ?? 0),
      cancellations,
      online_drivers: onlineDrivers,
      revenue: Number(revenue._sum.amount ?? 0),
      paid_rides: revenue._count,
      pending_drivers: pendingDrivers,
      open_sos: openSos,
    };
  }

  /** SPEC §7.4: snapshot; `admin:live` streams the same shape every 2 s. */
  @Get('live')
  snapshot() {
    return this.live.snapshot();
  }
}
