import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma.service';

type Db = Prisma.TransactionClient | PrismaService;

export const rideInclude = {
  rider: true,
  driver: { include: { user: true } },
  vehicle: true,
} satisfies Prisma.RideInclude;

export type RideWithRelations = Prisma.RideGetPayload<{ include: typeof rideInclude }>;

export interface RideCoords {
  pickup_lat: number;
  pickup_lng: number;
  drop_lat: number;
  drop_lng: number;
}

export type LoadedRide = RideWithRelations & { coords: RideCoords };

/** Rides with their PostGIS points (Prisma cannot read geography columns). */
@Injectable()
export class RideRepository {
  constructor(private readonly prisma: PrismaService) {}

  async coords(ids: string[], db: Db = this.prisma): Promise<Map<string, RideCoords>> {
    if (!ids.length) return new Map();
    const rows = await db.$queryRaw<(RideCoords & { id: string })[]>`
      SELECT id,
             ST_Y(pickup_point::geometry) AS pickup_lat, ST_X(pickup_point::geometry) AS pickup_lng,
             ST_Y(drop_point::geometry)   AS drop_lat,   ST_X(drop_point::geometry)   AS drop_lng
      FROM rides WHERE id IN (${Prisma.join(ids.map((id) => Prisma.sql`${id}::uuid`))})`;
    return new Map(rows.map(({ id, ...c }) => [id, c]));
  }

  async find(id: string, db: Db = this.prisma): Promise<LoadedRide | null> {
    const ride = await db.ride.findUnique({ where: { id }, include: rideInclude });
    if (!ride) return null;
    const coords = (await this.coords([id], db)).get(id)!;
    return { ...ride, coords };
  }

  async get(id: string, db: Db = this.prisma): Promise<LoadedRide> {
    const ride = await this.find(id, db);
    if (!ride) throw new NotFoundException('Ride not found');
    return ride;
  }

  async findMany(
    where: Prisma.RideWhereInput,
    args: { skip?: number; take?: number } = {},
  ): Promise<LoadedRide[]> {
    const rides = await this.prisma.ride.findMany({
      where,
      include: rideInclude,
      orderBy: { requestedAt: 'desc' },
      ...args,
    });
    const coords = await this.coords(rides.map((r) => r.id));
    return rides.map((r) => ({ ...r, coords: coords.get(r.id)! }));
  }

  /** Row lock for state transitions (SPEC §9.4 "SELECT … FOR UPDATE"). */
  async lock(id: string, db: Prisma.TransactionClient) {
    const [row] = await db.$queryRaw<
      { status: string }[]
    >`SELECT status FROM rides WHERE id = ${id}::uuid FOR UPDATE`;
    if (!row) throw new NotFoundException('Ride not found');
    return row;
  }
}
