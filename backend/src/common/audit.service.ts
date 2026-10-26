import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from './prisma.service';

type Db = Prisma.TransactionClient | PrismaService;

export interface AuditEntry {
  actorId: string;
  action: string;
  entity: string;
  entityId: string;
  before?: unknown;
  after?: unknown;
}

const json = (v: unknown) =>
  v === undefined ? undefined : (JSON.parse(JSON.stringify(v)) as Prisma.InputJsonValue);

/** SPEC §16: every admin mutation is written to audit_log. */
@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  log(entry: AuditEntry, db: Db = this.prisma) {
    return db.auditLog.create({
      data: {
        actorId: entry.actorId,
        action: entry.action,
        entity: entry.entity,
        entityId: entry.entityId,
        before: json(entry.before),
        after: json(entry.after),
      },
    });
  }
}
