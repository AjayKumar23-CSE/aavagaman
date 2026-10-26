import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, RideStatus } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { PrismaService } from '../../common/prisma.service';

const RATEABLE: RideStatus[] = ['COMPLETED', 'PAID'];

/** Ratings both ways (SPEC §7.2, §7.3); `users.rating_avg/rating_count` kept in step. */
@Injectable()
export class RatingsService {
  constructor(private readonly prisma: PrismaService) {}

  async rate(
    fromUserId: string,
    role: 'rider' | 'driver',
    rideId: string,
    stars: number,
    comment?: string,
  ) {
    const ride = await this.prisma.ride.findUnique({
      where: { id: rideId },
      select: { riderId: true, driverId: true, status: true },
    });
    const mine =
      ride && (role === 'rider' ? ride.riderId === fromUserId : ride.driverId === fromUserId);
    if (!ride || !mine) throw new NotFoundException('Ride not found');
    const toUserId = role === 'rider' ? ride.driverId : ride.riderId;
    if (!toUserId || !RATEABLE.includes(ride.status)) {
      throw new AppException(
        'RIDE_NOT_RATEABLE',
        'You can rate once the trip is completed',
        HttpStatus.CONFLICT,
      );
    }
    try {
      return await this.prisma.$transaction(async (tx) => {
        const rating = await tx.rating.create({
          data: { rideId, fromUserId, toUserId, stars, comment: comment?.trim() || null },
        });
        await tx.$executeRaw`
          UPDATE users
          SET rating_avg = round(((coalesce(rating_avg, 5) * coalesce(rating_count, 0)) + ${stars}) / (coalesce(rating_count, 0) + 1), 2),
              rating_count = coalesce(rating_count, 0) + 1
          WHERE id = ${toUserId}::uuid`;
        return {
          id: rating.id,
          ride_id: rideId,
          stars,
          comment: rating.comment,
          created_at: rating.createdAt,
        };
      });
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new AppException(
          'ALREADY_RATED',
          'You have already rated this ride',
          HttpStatus.CONFLICT,
        );
      }
      throw err;
    }
  }
}
