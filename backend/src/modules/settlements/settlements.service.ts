import { HttpStatus, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { AuditService } from '../../common/audit.service';
import { PrismaService } from '../../common/prisma.service';
import {
  istDate,
  istDayStart,
  istWeekStart,
  SettledRide,
  settlementTotals,
} from './settlement.math';

const WEEK_MS = 7 * 86_400_000;

type PaidRideRow = {
  driverId: string | null;
  finalFare: Prisma.Decimal | null;
  cancellationFee: Prisma.Decimal | null;
  payment: { method: string; amount: Prisma.Decimal } | null;
  fareConfig: { gstPct: Prisma.Decimal; commissionPct: Prisma.Decimal } | null;
};

const toSettled = (r: PaidRideRow): SettledRide => ({
  finalFare: Number(r.finalFare ?? 0),
  gstPct: Number(r.fareConfig?.gstPct ?? 5),
  commissionPct: Number(r.fareConfig?.commissionPct ?? 15),
  paidWith: r.payment?.method === 'cash' ? 'cash' : 'online',
  amountPaid: Number(r.payment?.amount ?? 0),
});

@Injectable()
export class SettlementsService {
  private readonly logger = new Logger(SettlementsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  private paidRides(where: Prisma.RideWhereInput) {
    return this.prisma.ride.findMany({
      where: { ...where, status: 'PAID' },
      select: {
        driverId: true,
        finalFare: true,
        cancellationFee: true,
        payment: { select: { method: true, amount: true } },
        fareConfig: { select: { gstPct: true, commissionPct: true } },
      },
    });
  }

  /** GET /driver/earnings?period=today|week (SPEC §7.3). */
  async earnings(driverId: string, period: 'today' | 'week', now = new Date()) {
    const from = period === 'today' ? istDayStart(now) : istWeekStart(now);
    const rides = await this.paidRides({ driverId, paidAt: { gte: from, lte: now } });
    const t = settlementTotals(rides.map(toSettled));
    return {
      period,
      from,
      to: now,
      rides: t.rides_count,
      gross: t.gross_fares,
      commission: t.commission,
      gst: t.gst_on_gross,
      net: Math.round((t.gross_fares - t.commission - t.gst_on_gross) * 100) / 100,
      cash_collected: t.cash_collected,
      online: t.online_collected,
    };
  }

  /** Creates/refreshes unsettled rows for the Mon–Sun week starting at `weekStart` (default: last week). */
  async generate(weekStart?: Date, now = new Date()) {
    const start = weekStart
      ? istWeekStart(weekStart)
      : new Date(istWeekStart(now).getTime() - WEEK_MS);
    const end = new Date(start.getTime() + WEEK_MS);
    if (end > now) {
      throw new AppException(
        'WEEK_NOT_OVER',
        'Settlements can be generated once the week has ended',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    const rides = await this.paidRides({
      paidAt: { gte: start, lt: end },
      driverId: { not: null },
    });
    const byDriver = new Map<string, SettledRide[]>();
    for (const r of rides)
      byDriver.set(r.driverId!, [...(byDriver.get(r.driverId!) ?? []), toSettled(r)]);

    const periodStart = istDate(start);
    const periodEnd = istDate(new Date(end.getTime() - 86_400_000));
    const rows = [];
    for (const [driverId, list] of byDriver) {
      const t = settlementTotals(list);
      const existing = await this.prisma.driverSettlement.findUnique({
        where: { driverId_periodStart: { driverId, periodStart } },
      });
      if (existing?.settledAt) {
        rows.push(existing);
        continue; // never rewrite a settled statement
      }
      rows.push(
        await this.prisma.driverSettlement.upsert({
          where: { driverId_periodStart: { driverId, periodStart } },
          create: {
            driverId,
            periodStart,
            periodEnd,
            ridesCount: t.rides_count,
            grossFares: t.gross_fares,
            commission: t.commission,
            cashCollected: t.cash_collected,
            onlineCollected: t.online_collected,
            amountPayable: t.amount_payable,
          },
          update: {
            ridesCount: t.rides_count,
            grossFares: t.gross_fares,
            commission: t.commission,
            cashCollected: t.cash_collected,
            onlineCollected: t.online_collected,
            amountPayable: t.amount_payable,
          },
        }),
      );
    }
    this.logger.log(
      `settlements for week of ${periodStart.toISOString().slice(0, 10)}: ${rows.length} driver(s)`,
    );
    return {
      period_start: periodStart,
      period_end: periodEnd,
      settlements: rows.map(presentSettlement),
    };
  }

  async list(weekStart?: Date) {
    const where: Prisma.DriverSettlementWhereInput = weekStart
      ? { periodStart: istDate(istWeekStart(weekStart)) }
      : {};
    const rows = await this.prisma.driverSettlement.findMany({
      where,
      include: { driver: { include: { user: { select: { name: true, phone: true } } } } },
      orderBy: [{ periodStart: 'desc' }, { amountPayable: 'desc' }],
    });
    return rows.map((r) => ({
      ...presentSettlement(r),
      driver_name: r.driver.user.name,
      driver_phone: r.driver.user.phone,
    }));
  }

  async settle(adminId: string, id: string, reference: string) {
    const row = await this.prisma.driverSettlement.findUnique({ where: { id } });
    if (!row) throw new NotFoundException('Settlement not found');
    if (row.settledAt)
      throw new AppException(
        'ALREADY_SETTLED',
        'This settlement is already marked settled',
        HttpStatus.CONFLICT,
      );
    const updated = await this.prisma.driverSettlement.update({
      where: { id },
      data: { settledAt: new Date(), settledById: adminId, reference },
    });
    await this.audit.log({
      actorId: adminId,
      action: 'settlement.settle',
      entity: 'driver_settlement',
      entityId: id,
      before: presentSettlement(row),
      after: presentSettlement(updated),
    });
    return presentSettlement(updated);
  }
}

export function presentSettlement(s: {
  id: string;
  driverId: string;
  periodStart: Date;
  periodEnd: Date;
  ridesCount: number | null;
  grossFares: Prisma.Decimal | null;
  commission: Prisma.Decimal | null;
  cashCollected: Prisma.Decimal | null;
  onlineCollected: Prisma.Decimal | null;
  amountPayable: Prisma.Decimal | null;
  settledAt: Date | null;
  reference: string | null;
  settledById: string | null;
}) {
  const n = (d: Prisma.Decimal | null) => (d === null ? 0 : Number(d));
  return {
    id: s.id,
    driver_id: s.driverId,
    period_start: s.periodStart.toISOString().slice(0, 10),
    period_end: s.periodEnd.toISOString().slice(0, 10),
    rides_count: s.ridesCount ?? 0,
    gross_fares: n(s.grossFares),
    commission: n(s.commission),
    cash_collected: n(s.cashCollected),
    online_collected: n(s.onlineCollected),
    amount_payable: n(s.amountPayable),
    settled_at: s.settledAt,
    reference: s.reference,
    settled_by: s.settledById,
  };
}
