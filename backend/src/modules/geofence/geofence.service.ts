import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../common/prisma.service';

@Injectable()
export class GeofenceService {
  constructor(private readonly prisma: PrismaService) {}

  /** SPEC §9.1 */
  async isInsideServiceArea(lat: number, lng: number): Promise<boolean> {
    const [row] = await this.prisma.$queryRaw<{ inside: boolean }[]>`
      SELECT EXISTS (
        SELECT 1 FROM service_areas
        WHERE active AND ST_Covers(polygon, ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography)
      ) AS inside`;
    return row.inside;
  }
}
