import { randomBytes } from 'node:crypto';
import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { AppException } from '../../common/app.exception';
import { PrismaService } from '../../common/prisma.service';
import { TokenService } from '../auth/token.service';
import { presentUser } from './user.presenter';
import { UpdateMeDto } from './users.dto';

const ACTIVE_RIDE = ['REQUESTED', 'ACCEPTED', 'ARRIVED', 'STARTED'] as const;

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TokenService,
  ) {}

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');
    return presentUser(user);
  }

  async update(userId: string, dto: UpdateMeDto) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: {
        name: dto.name?.trim(),
        email: dto.email === null ? null : dto.email?.trim().toLowerCase(),
      },
    });
    return presentUser(user);
  }

  async setFcmToken(userId: string, token: string) {
    await this.prisma.user.update({ where: { id: userId }, data: { fcmToken: token } });
  }

  /**
   * SPEC §16: anonymise, keep rides for accounting. `users.phone` is VARCHAR(15),
   * so the placeholder is "del:" + 11 random chars rather than a full UUID (D-012).
   */
  async deleteAccount(userId: string) {
    const active = await this.prisma.ride.count({
      where: {
        status: { in: [...ACTIVE_RIDE] },
        OR: [{ riderId: userId }, { driverId: userId }],
      },
    });
    if (active) {
      throw new AppException(
        'ACTIVE_RIDE',
        'Finish or cancel your ride first',
        HttpStatus.CONFLICT,
      );
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: {
        phone: 'del:' + randomBytes(8).toString('base64url').slice(0, 11),
        name: null,
        email: null,
        fcmToken: null,
        status: 'blocked',
      },
    });
    await this.tokens.deleteAll(userId);
  }
}
