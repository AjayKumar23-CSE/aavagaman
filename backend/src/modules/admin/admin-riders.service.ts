import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { AuditService } from '../../common/audit.service';
import { Page, skipTake } from '../../common/pagination';
import { PrismaService } from '../../common/prisma.service';
import { TokenService } from '../auth/token.service';
import { presentUser } from '../users/user.presenter';
import { ListRidersQuery } from './dto/admin.dto';

@Injectable()
export class AdminRidersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TokenService,
    private readonly audit: AuditService,
  ) {}

  async list(
    q: ListRidersQuery,
  ): Promise<Page<ReturnType<typeof presentUser> & { rides_count: number }>> {
    const term = q.q?.trim();
    const where: Prisma.UserWhereInput = {
      role: 'rider',
      ...(term
        ? {
            OR: [
              { name: { contains: term, mode: 'insensitive' } },
              { phone: { contains: term.replace(/\s/g, '') } },
              { email: { contains: term, mode: 'insensitive' } },
            ],
          }
        : {}),
    };
    const [rows, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        ...skipTake(q),
        include: { _count: { select: { ridesAsRider: true } } },
      }),
      this.prisma.user.count({ where }),
    ]);
    return {
      data: rows.map((u) => ({ ...presentUser(u), rides_count: u._count.ridesAsRider })),
      page: q.page,
      limit: q.limit,
      total,
    };
  }

  async setBlocked(adminId: string, riderId: string, blocked: boolean, reason?: string) {
    const user = await this.prisma.user.findFirst({ where: { id: riderId, role: 'rider' } });
    if (!user) throw new NotFoundException('Rider not found');
    if (user.phone.startsWith('del:'))
      throw new AppException('ACCOUNT_DELETED', 'This account was deleted', HttpStatus.CONFLICT);
    const updated = await this.prisma.user.update({
      where: { id: riderId },
      data: { status: blocked ? 'blocked' : 'active' },
    });
    if (blocked) await this.tokens.deleteAll(riderId);
    await this.audit.log({
      actorId: adminId,
      action: blocked ? 'rider.block' : 'rider.unblock',
      entity: 'user',
      entityId: riderId,
      before: { status: user.status },
      after: { status: updated.status, reason: reason ?? null },
    });
    return presentUser(updated);
  }
}
