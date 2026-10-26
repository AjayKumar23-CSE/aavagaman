/**
 * Needs a migrated + seeded Postgres/PostGIS and Redis (CI service containers,
 * or `docker compose -f infra/docker-compose.yml up postgres redis`).
 */
import { NestExpressApplication } from '@nestjs/platform-express';
import { PrismaService } from '../../src/common/prisma.service';
import { api, createTestApp } from './app';

describe('Phase 0 foundation (e2e)', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createTestApp();
    prisma = app.get(PrismaService);
  });

  afterAll(async () => {
    await app?.close();
  });

  it('GET /health reports db and redis up', async () => {
    const res = await api(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ status: 'ok', db: true, redis: true });
    expect(typeof res.body.osrm).toBe('boolean');
  });

  it('seed created the admin, fare config and NCR polygon', async () => {
    expect(await prisma.user.count({ where: { role: 'admin' } })).toBeGreaterThanOrEqual(1);

    // One starting version per vehicle class (D-056); sedan keeps the SPEC numbers.
    expect(await prisma.fareConfig.count()).toBeGreaterThanOrEqual(4);
    const fc = await prisma.fareConfig.findFirstOrThrow({
      where: { vehicleType: 'sedan' },
      orderBy: { effectiveFrom: 'asc' },
    });
    expect(fc.baseFare.toNumber()).toBe(50);
    expect(fc.perKm.toNumber()).toBe(12);
    expect(fc.perMin.toNumber()).toBe(1.5);
    expect(fc.minFare.toNumber()).toBe(80);
    expect(fc.cancellationFee.toNumber()).toBe(30);
    expect(fc.commissionPct.toNumber()).toBe(15);
  });

  it.each([
    ['Connaught Place', 28.6315, 77.2167, true],
    ['Cyber City, Gurugram', 28.495, 77.089, true],
    ['Noida Sector 18', 28.57, 77.325, true],
    ['Meerut', 28.98, 77.7, false],
  ])('geofence: %s → inside=%p', async (_name, lat, lng, expected) => {
    const [{ inside }] = await prisma.$queryRaw<{ inside: boolean }[]>`
      SELECT EXISTS (
        SELECT 1 FROM service_areas
        WHERE active AND ST_Covers(polygon, ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography)
      ) AS inside`;
    expect(inside).toBe(expected);
  });

  it('enforces one active ride per driver at the DB level', async () => {
    const [{ indexdef }] = await prisma.$queryRaw<{ indexdef: string }[]>`
      SELECT indexdef FROM pg_indexes WHERE indexname = 'one_active_ride_per_driver'`;
    expect(indexdef).toMatch(/UNIQUE/);
    expect(indexdef).toMatch(/ACCEPTED/);
  });
});
