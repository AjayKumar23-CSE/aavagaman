import { HttpStatus, Injectable } from '@nestjs/common';
import { AppException } from '../../common/app.exception';
import { PrismaService } from '../../common/prisma.service';
import { commissionOf, gstOf } from '../fare/fare.engine';

const IST_MS = 5.5 * 3_600_000;
const istDay = (d: Date) => new Date(d.getTime() + IST_MS).toISOString().slice(0, 10);
const dayStartUtc = (ymd: string) => new Date(Date.parse(ymd + 'T00:00:00Z') - IST_MS);

export interface DailyRow {
  day: string;
  requested: number;
  completed: number;
  cancelled: number;
  no_driver: number;
  paid_rides: number;
  revenue: number;
  gross_fares: number;
  gst: number;
  commission: number;
  cash: number;
  online: number;
}

export const DAILY_COLUMNS: (keyof DailyRow)[] = [
  'day',
  'requested',
  'completed',
  'cancelled',
  'no_driver',
  'paid_rides',
  'revenue',
  'gross_fares',
  'gst',
  'commission',
  'cash',
  'online',
];

export function toCsv(rows: DailyRow[]): string {
  const lines = [DAILY_COLUMNS.join(',')];
  for (const r of rows) lines.push(DAILY_COLUMNS.map((c) => String(r[c])).join(','));
  return lines.join('\r\n') + '\r\n';
}

/** SPEC §7.4 GET /admin/reports/daily — per IST day, inclusive range. */
@Injectable()
export class AdminReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async daily(fromYmd: string, toYmd: string): Promise<DailyRow[]> {
    const from = dayStartUtc(fromYmd);
    const to = new Date(dayStartUtc(toYmd).getTime() + 86_400_000);
    if (!(from < to) || to.getTime() - from.getTime() > 366 * 86_400_000) {
      throw new AppException(
        'INVALID_RANGE',
        'from must be on or before to, and the range at most a year',
        HttpStatus.BAD_REQUEST,
      );
    }
    const rows = new Map<string, DailyRow>();
    for (let t = from.getTime(); t < to.getTime(); t += 86_400_000) {
      const day = istDay(new Date(t));
      rows.set(day, {
        day,
        requested: 0,
        completed: 0,
        cancelled: 0,
        no_driver: 0,
        paid_rides: 0,
        revenue: 0,
        gross_fares: 0,
        gst: 0,
        commission: 0,
        cash: 0,
        online: 0,
      });
    }
    const r2 = (n: number) => Math.round(n * 100) / 100;

    const requested = await this.prisma.ride.findMany({
      where: { requestedAt: { gte: from, lt: to } },
      select: { requestedAt: true, status: true },
    });
    for (const r of requested) {
      const row = rows.get(istDay(r.requestedAt!));
      if (!row) continue;
      row.requested++;
      if (r.status === 'COMPLETED' || r.status === 'PAID') row.completed++;
      if (r.status === 'CANCELLED') row.cancelled++;
      if (r.status === 'NO_DRIVER') row.no_driver++;
    }
    const paid = await this.prisma.ride.findMany({
      where: { status: 'PAID', paidAt: { gte: from, lt: to } },
      select: {
        paidAt: true,
        finalFare: true,
        payment: { select: { method: true, amount: true } },
        fareConfig: { select: { gstPct: true, commissionPct: true } },
      },
    });
    for (const r of paid) {
      const row = rows.get(istDay(r.paidAt!));
      if (!row) continue;
      const fare = Number(r.finalFare ?? 0);
      const cfg = {
        gstPct: Number(r.fareConfig?.gstPct ?? 5),
        commissionPct: Number(r.fareConfig?.commissionPct ?? 15),
      };
      const amount = Number(r.payment?.amount ?? fare);
      row.paid_rides++;
      row.revenue = r2(row.revenue + amount);
      row.gross_fares = r2(row.gross_fares + fare);
      row.gst = r2(row.gst + gstOf(fare, cfg.gstPct));
      row.commission = r2(row.commission + commissionOf(fare, cfg));
      if (r.payment?.method === 'cash') row.cash = r2(row.cash + amount);
      else row.online = r2(row.online + amount);
    }
    return [...rows.values()];
  }
}
