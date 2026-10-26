import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import type { AuthUser } from '../../common/auth/auth-user';
import type { LatLng } from '../../common/geo/geo';
import { PrismaService } from '../../common/prisma.service';
import { SmsService } from '../notifications/sms.service';
import { RealtimeEmitter } from '../realtime/realtime.emitter';

/** SPEC §7.2 POST /rides/:id/sos: the app dials 112 itself; this records and alerts admins. */
@Injectable()
export class SosService {
  private readonly logger = new Logger(SosService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly rt: RealtimeEmitter,
    private readonly sms: SmsService,
  ) {}

  async raise(user: AuthUser, rideId: string, point: LatLng) {
    const ride = await this.prisma.ride.findUnique({
      where: { id: rideId },
      select: { riderId: true, driverId: true },
    });
    const party = ride && (ride.riderId === user.id || ride.driverId === user.id);
    if (!ride || !party) throw new NotFoundException('Ride not found');

    const [row] = await this.prisma.$queryRaw<{ id: string; created_at: Date }[]>`
      INSERT INTO sos_alerts (ride_id, user_id, point)
      VALUES (${rideId}::uuid, ${user.id}::uuid, ST_SetSRID(ST_MakePoint(${point.lng}, ${point.lat}), 4326)::geography)
      RETURNING id, created_at`;

    const payload = {
      sos_id: row.id,
      ride_id: rideId,
      user_id: user.id,
      role: user.role,
      lat: point.lat,
      lng: point.lng,
      at: row.created_at.toISOString(),
    };
    this.rt.toAdmins('sos:alert', payload);
    void this.alertAdmins(
      `SOS from ${user.role} on ride ${rideId.slice(0, 8)}: https://maps.google.com/?q=${point.lat},${point.lng}`,
    );
    return { id: row.id, created_at: row.created_at };
  }

  private async alertAdmins(message: string) {
    try {
      const admins = await this.prisma.user.findMany({
        where: { role: 'admin', status: 'active', NOT: { phone: { startsWith: 'del:' } } },
        select: { phone: true },
      });
      await Promise.all(admins.map((a) => this.sms.sendAlert(a.phone, message)));
    } catch (err) {
      this.logger.error(`SOS admin SMS failed: ${(err as Error).message}`);
    }
  }
}
