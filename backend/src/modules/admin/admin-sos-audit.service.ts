import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { AuditService } from '../../common/audit.service';
import { Page, skipTake } from '../../common/pagination';
import { PrismaService } from '../../common/prisma.service';
import { AuditQuery, SosQuery } from './dto/admin.dto';

interface SosRow {
  id: string;
  ride_id: string | null;
  user_id: string;
  user_name: string | null;
  user_phone: string;
  user_role: string;
  lat: number | null;
  lng: number | null;
  acknowledged_by: string | null;
  acknowledged_at: Date | null;
  created_at: Date;
}

@Injectable()
export class AdminSosAuditService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async listSos(q: SosQuery): Promise<Page<SosRow>> {
    const ackFilter =
      q.acknowledged === undefined
        ? Prisma.sql``
        : q.acknowledged
          ? Prisma.sql`WHERE s.acknowledged_at IS NOT NULL`
          : Prisma.sql`WHERE s.acknowledged_at IS NULL`;
    const { skip, take } = skipTake(q);
    const [rows, [{ n }]] = await Promise.all([
      this.prisma.$queryRaw<SosRow[]>`
        SELECT s.id, s.ride_id, s.user_id, u.name AS user_name, u.phone AS user_phone, u.role::text AS user_role,
               ST_Y(s.point::geometry) AS lat, ST_X(s.point::geometry) AS lng,
               s.acknowledged_by, s.acknowledged_at, s.created_at
        FROM sos_alerts s JOIN users u ON u.id = s.user_id
        ${ackFilter}
        ORDER BY s.created_at DESC LIMIT ${take} OFFSET ${skip}`,
      this.prisma.$queryRaw<{ n: bigint }[]>`SELECT count(*) AS n FROM sos_alerts s ${ackFilter}`,
    ]);
    return { data: rows, page: q.page, limit: q.limit, total: Number(n) };
  }

  async ackSos(adminId: string, id: string) {
    const alert = await this.prisma.sosAlert.findUnique({ where: { id } });
    if (!alert) throw new NotFoundException('SOS alert not found');
    if (alert.acknowledgedAt)
      throw new AppException('ALREADY_ACKNOWLEDGED', 'Already acknowledged', HttpStatus.CONFLICT);
    const updated = await this.prisma.sosAlert.update({
      where: { id },
      data: { acknowledgedById: adminId, acknowledgedAt: new Date() },
    });
    await this.audit.log({
      actorId: adminId,
      action: 'sos.ack',
      entity: 'sos_alert',
      entityId: id,
      after: { acknowledged_at: updated.acknowledgedAt },
    });
    return {
      id: updated.id,
      ride_id: updated.rideId,
      user_id: updated.userId,
      acknowledged_by: updated.acknowledgedById,
      acknowledged_at: updated.acknowledgedAt,
      created_at: updated.createdAt,
    };
  }

  async listAudit(q: AuditQuery) {
    const where: Prisma.AuditLogWhereInput = {
      entity: q.entity,
      entityId: q.entity_id,
      actorId: q.actor_id,
    };
    const [rows, total] = await Promise.all([
      this.prisma.auditLog.findMany({ where, orderBy: { id: 'desc' }, ...skipTake(q) }),
      this.prisma.auditLog.count({ where }),
    ]);
    const actorIds = [
      ...new Set(rows.map((r) => r.actorId).filter((x): x is string => Boolean(x))),
    ];
    const actors = actorIds.length
      ? await this.prisma.user.findMany({
          where: { id: { in: actorIds } },
          select: { id: true, name: true, email: true },
        })
      : [];
    const byId = new Map(actors.map((a) => [a.id, a]));
    return {
      data: rows.map((r) => ({
        id: Number(r.id),
        actor_id: r.actorId,
        actor_name: r.actorId
          ? (byId.get(r.actorId)?.name ?? byId.get(r.actorId)?.email ?? null)
          : null,
        action: r.action,
        entity: r.entity,
        entity_id: r.entityId,
        before: r.before,
        after: r.after,
        at: r.createdAt,
      })),
      page: q.page,
      limit: q.limit,
      total,
    };
  }
}
