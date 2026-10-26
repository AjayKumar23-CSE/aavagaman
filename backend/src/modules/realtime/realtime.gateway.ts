import { Logger, OnModuleDestroy } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
} from '@nestjs/websockets';
import type { UserRole } from '@prisma/client';
import { IsUUID } from 'class-validator';
import type { Namespace, Socket } from 'socket.io';
import { AppException } from '../../common/app.exception';
import type { AuthUser } from '../../common/auth/auth-user';
import { DriverFixDto } from '../../common/geo/geo.dto';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { loadConfig } from '../../config/config.module';
import { LiveService } from '../admin/live.service';
import { PresenceService } from '../location/presence.service';
import { MatchingService } from '../matching/matching.service';
import { DriverRidesService } from '../rides/driver-rides.service';
import { rideStatusEvent } from '../rides/ride.presenter';
import { RideRepository } from '../rides/ride.repository';
import { RIDER_OPEN_STATUSES } from '../rides/rides.service';
import { DRIVER_OPEN_STATUSES } from '../rides/driver-rides.service';
import { ADMIN_ROOM, RT_NAMESPACE, userRoom } from './realtime.emitter';
import { ack, parseWs } from './ws-utils';

class RideIdDto {
  @IsUUID()
  ride_id: string;
}

type AuthedSocket = Socket & { data: { user: AuthUser } };

const forbidden = () => new AppException('FORBIDDEN', 'Not allowed for this role', 403);
const requireRole = (s: AuthedSocket, role: UserRole) => {
  if (s.data.user.role !== role) throw forbidden();
};

/** SPEC §8: admin:live is batched every 2 s. */
export const ADMIN_LIVE_INTERVAL_MS = 2000;

/** Socket.io namespace /rt (SPEC §8). */
@WebSocketGateway({
  namespace: RT_NAMESPACE,
  cors: { origin: loadConfig().ADMIN_ORIGIN, credentials: true },
})
export class RealtimeGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect, OnModuleDestroy
{
  private readonly logger = new Logger(RealtimeGateway.name);
  private liveTimer?: NodeJS.Timeout;

  constructor(
    private readonly jwt: JwtService,
    private readonly redis: RedisService,
    private readonly presence: PresenceService,
    private readonly matching: MatchingService,
    private readonly driverRides: DriverRidesService,
    private readonly rides: RideRepository,
    private readonly live: LiveService,
  ) {}

  /** Handshake auth (SPEC §8): a bad token gets `connect_error` and never joins a room. */
  afterInit(nsp: Namespace) {
    // Live map feed, only while an admin is connected to this node.
    this.liveTimer = setInterval(() => {
      if (!nsp.adapter.rooms.get(ADMIN_ROOM)?.size) return;
      this.live
        .snapshot()
        .then((snap) => nsp.to(ADMIN_ROOM).emit('admin:live', snap))
        .catch((e: Error) => this.logger.warn(`admin:live: ${e.message}`));
    }, ADMIN_LIVE_INTERVAL_MS);
    this.liveTimer.unref();

    nsp.use((socket, nextFn) => {
      const token = (socket.handshake.auth as { token?: string } | undefined)?.token ?? '';
      this.jwt
        .verifyAsync<{ sub: string; role: UserRole; typ: string }>(token)
        .then((claims) => {
          if (claims.typ !== 'access') throw new Error('not an access token');
          socket.data.user = { id: claims.sub, role: claims.role } satisfies AuthUser;
          nextFn();
        })
        .catch(() => nextFn(new Error('UNAUTHORIZED')));
    });
  }

  async handleConnection(socket: Socket) {
    const s = socket as AuthedSocket;
    const { id, role } = s.data.user;
    await s.join(userRoom(id));
    if (role === 'admin') await s.join(ADMIN_ROOM);
    await this.redis.sadd(K.wsUser(id), s.id);
    // "On connect the server re-sends the current active ride" (SPEC §8).
    await this.resendState(s).catch((e: Error) => this.logger.warn(`resend: ${e.message}`));
  }

  onModuleDestroy() {
    if (this.liveTimer) clearInterval(this.liveTimer);
  }

  async handleDisconnect(socket: Socket) {
    const user = (socket as AuthedSocket).data?.user;
    if (user) await this.redis.srem(K.wsUser(user.id), socket.id);
  }

  private async resendState(s: AuthedSocket) {
    const { id, role } = s.data.user;
    if (role === 'rider') {
      const [ride] = await this.rides.findMany(
        { riderId: id, status: { in: RIDER_OPEN_STATUSES } },
        { take: 1 },
      );
      if (ride) s.emit('ride:status', rideStatusEvent(ride, 'rider'));
    } else if (role === 'driver') {
      const [ride] = await this.rides.findMany(
        { driverId: id, status: { in: DRIVER_OPEN_STATUSES } },
        { take: 1 },
      );
      if (ride) s.emit('ride:status', rideStatusEvent(ride, 'driver'));
      for (const offer of await this.matching.pendingOffersFor(id)) s.emit('ride:offer', offer);
    }
  }

  @SubscribeMessage('driver:location')
  location(@ConnectedSocket() s: AuthedSocket, @MessageBody() body: unknown) {
    return ack(async () => {
      requireRole(s, 'driver');
      await this.presence.ingest(s.data.user.id, await parseWs(DriverFixDto, body));
    });
  }

  @SubscribeMessage('driver:offer:accept')
  accept(@ConnectedSocket() s: AuthedSocket, @MessageBody() body: unknown) {
    return ack(async () => {
      requireRole(s, 'driver');
      const { ride_id } = await parseWs(RideIdDto, body);
      return this.driverRides.accept(s.data.user.id, ride_id);
    });
  }

  @SubscribeMessage('driver:offer:reject')
  reject(@ConnectedSocket() s: AuthedSocket, @MessageBody() body: unknown) {
    return ack(async () => {
      requireRole(s, 'driver');
      const { ride_id } = await parseWs(RideIdDto, body);
      await this.driverRides.reject(s.data.user.id, ride_id);
    });
  }

  /** Re-sends the ride's status and the driver's last known position. */
  @SubscribeMessage('rider:subscribe')
  subscribe(@ConnectedSocket() s: AuthedSocket, @MessageBody() body: unknown) {
    return ack(async () => {
      requireRole(s, 'rider');
      const { ride_id } = await parseWs(RideIdDto, body);
      const ride = await this.rides.find(ride_id);
      if (!ride || ride.riderId !== s.data.user.id)
        throw new AppException('NOT_FOUND', 'Ride not found', 404);
      s.emit('ride:status', rideStatusEvent(ride, 'rider'));
      if (ride.driverId) {
        const pos = await this.presence.lastPosition(ride.driverId);
        if (pos)
          s.emit('driver:position', {
            ride_id: ride.id,
            driver_id: ride.driverId,
            lat: pos.lat,
            lng: pos.lng,
            heading: pos.heading,
          });
      }
    });
  }

  @SubscribeMessage('admin:subscribe')
  adminSubscribe(@ConnectedSocket() s: AuthedSocket) {
    return ack(async () => {
      requireRole(s, 'admin');
      await s.join(ADMIN_ROOM);
    });
  }
}
