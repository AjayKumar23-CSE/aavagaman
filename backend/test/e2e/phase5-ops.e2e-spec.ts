/** Phase 5 operational bits: GET /metrics (SPEC §7.5) and the nightly retention job (SPEC §5). */
import { NestExpressApplication } from '@nestjs/platform-express';
import { PrismaService } from '../../src/common/prisma.service';
import { SystemProcessor } from '../../src/modules/matching/system.processor';
import { api, createTestApp } from './app';
import { CP, INDIA_GATE, loginAs } from './fixtures';

describe('Phase 5: metrics and retention (e2e)', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createTestApp({ worker: true });
    prisma = app.get(PrismaService);
  });

  afterAll(async () => {
    await app?.close();
  });

  it('GET /metrics needs the token and returns Prometheus text', async () => {
    await api(app).get('/metrics').expect(401);
    await api(app).get('/metrics?token=wrong').expect(401);
    const res = await api(app)
      .get('/metrics')
      .set('Authorization', 'Bearer metrics-test-token')
      .expect(200);
    expect(res.headers['content-type']).toMatch(/text\/plain/);
    expect(res.text).toMatch(/^# TYPE drivers_online gauge$/m);
    expect(res.text).toMatch(/^drivers_online \d+$/m);
    expect(res.text).toMatch(/^rides_active \d+$/m);
    expect(res.text).toMatch(/^process_uptime_seconds \d+$/m);
    await api(app).get('/metrics?token=metrics-test-token').expect(200);
  });

  it('retention deletes ride_tracks older than TRACK_RETENTION_DAYS and keeps recent ones', async () => {
    const rider = await loginAs(app, 'rider');
    const est = (
      await api(app)
        .post('/v1/fare/estimate')
        .set('Authorization', `Bearer ${rider.token}`)
        .send({ pickup: CP, drop: INDIA_GATE })
        .expect(200)
    ).body;
    const ride = (
      await api(app)
        .post('/v1/rides')
        .set('Authorization', `Bearer ${rider.token}`)
        .send({
          pickup: CP,
          drop: INDIA_GATE,
          fare_config_id: est.fare_config_id,
          payment_method: 'cash',
        })
        .expect(201)
    ).body;
    await api(app)
      .post(`/v1/rides/${ride.id}/cancel`)
      .set('Authorization', `Bearer ${rider.token}`)
      .send({})
      .expect(200);

    const old = new Date(Date.now() - 40 * 86_400_000);
    const recent = new Date(Date.now() - 86_400_000);
    for (const at of [old, recent]) {
      await prisma.$executeRaw`
        INSERT INTO ride_tracks (ride_id, recorded_at, point)
        VALUES (${ride.id}::uuid, ${at}, ST_SetSRID(ST_MakePoint(${CP.lng}, ${CP.lat}), 4326)::geography)`;
    }
    const deleted = await app.get(SystemProcessor).retention(30);
    expect(deleted).toBeGreaterThanOrEqual(1);
    const left = await prisma.rideTrack.findMany({ where: { rideId: ride.id } });
    expect(left.map((t) => t.recordedAt.getTime())).toEqual([recent.getTime()]);
  });
});
