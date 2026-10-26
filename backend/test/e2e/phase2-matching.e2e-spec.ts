/**
 * SPEC §20 Phase 2 acceptance, API level (timers shortened in .env.test):
 * the nearest drivers are offered together (D-055); an ignored round moves on to
 * the next drivers;
 * simultaneous accepts → exactly one wins; rider sees the car move within 2 s;
 * a silent driver is marked offline within the heartbeat window; pickup outside
 * NCR is rejected.
 */
import { NestExpressApplication } from '@nestjs/platform-express';
import type { Socket } from 'socket.io-client';
import { PrismaService } from '../../src/common/prisma.service';
import { RedisService } from '../../src/common/redis.service';
import { api, connectSocket, createTestApp, next, sleep } from './app';
import {
  adminLogin,
  approvedDriver,
  bearer,
  CP,
  FARTHER_CP,
  GREATER_NOIDA,
  INDIA_GATE,
  loginAs,
  MEERUT,
  NEAR_CP,
  Session,
} from './fixtures';

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

describe('Phase 2: live location and matching (e2e)', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;
  let redis: RedisService;
  let admin: string;
  const sockets: Socket[] = [];
  const keepalives: NodeJS.Timeout[] = [];

  beforeAll(async () => {
    app = await createTestApp({ worker: true });
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);
    admin = await adminLogin(app);
  });

  afterEach(() => {
    keepalives.splice(0).forEach(clearInterval);
  });

  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    await app?.close();
  });

  const socketFor = async (s: Session) => {
    const sock = await connectSocket(app, s.token);
    sockets.push(sock);
    return sock;
  };

  /** Online driver with a socket that keeps sending its position (heartbeat). */
  const onlineDriver = async (
    pos: { lat: number; lng: number },
    name?: string,
    vehicleType?: string,
  ) => {
    const d = await approvedDriver(app, admin, name, vehicleType);
    await api(app).post('/v1/driver/online').set(bearer(d.token)).send(pos).expect(204);
    const socket = await socketFor(d);
    keepalives.push(
      setInterval(
        () => socket.emit('driver:location', { ...pos, heading: 90, speed: 0, accuracy: 5 }),
        1000,
      ),
    );
    return { ...d, socket };
  };

  const goOffline = (d: Session) =>
    api(app).post('/v1/driver/offline').set(bearer(d.token)).expect(204);

  const estimate = async (rider: Session, pickup = CP, drop = INDIA_GATE) =>
    (
      await api(app)
        .post('/v1/fare/estimate')
        .set(bearer(rider.token))
        .send({ pickup, drop })
        .expect(200)
    ).body as Json;

  const requestRide = async (rider: Session, pickup = CP, drop = INDIA_GATE) => {
    const est = await estimate(rider, pickup, drop);
    return api(app)
      .post('/v1/rides')
      .set(bearer(rider.token))
      .send({ pickup, drop, fare_config_id: est.fare_config_id, payment_method: 'cash' });
  };

  describe('estimate and geofence', () => {
    it('returns a fare estimate with service-area flags', async () => {
      const rider = await loginAs(app, 'rider');
      const est = await estimate(rider);
      expect(est).toMatchObject({ currency: 'INR', in_service_area: { pickup: true, drop: true } });
      expect(est.distance_m).toBeGreaterThan(2000);
      expect(est.fare_min).toBeLessThan(est.fare_max);
      expect(est.fare_min).toBeGreaterThanOrEqual(76); // min fare 80 × 0.95
      // One option per vehicle class (D-056); the top-level fare is the sedan one.
      expect(est.vehicle_type).toBe('sedan');
      expect(est.options.map((o: Json) => o.vehicle_type)).toEqual(['bike', 'auto', 'mini', 'sedan']);
      const sedan = est.options.find((o: Json) => o.vehicle_type === 'sedan');
      const bike = est.options.find((o: Json) => o.vehicle_type === 'bike');
      expect(sedan.fare_config_id).toBe(est.fare_config_id);
      expect(sedan).toMatchObject({ seats: 4, fare_min: est.fare_min, fare_max: est.fare_max });
      expect(bike.seats).toBe(1);
      expect(bike.fare_max).toBeLessThan(sedan.fare_min);

      const out = await estimate(rider, CP, MEERUT);
      expect(out.in_service_area).toEqual({ pickup: true, drop: false });
    });

    it('rejects a pickup outside NCR with 422 OUTSIDE_SERVICE_AREA', async () => {
      const rider = await loginAs(app, 'rider');
      const res = await requestRide(rider, MEERUT, CP);
      expect(res.status).toBe(422);
      expect(res.body.error.code).toBe('OUTSIDE_SERVICE_AREA');
    });

    it('allows a drop outside NCR', async () => {
      const rider = await loginAs(app, 'rider');
      const res = await requestRide(rider, GREATER_NOIDA, MEERUT);
      expect(res.status).toBe(201);
      await api(app)
        .post(`/v1/rides/${res.body.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
    });
  });

  describe('presence', () => {
    it('only approved drivers can go online', async () => {
      const pending = await loginAs(app, 'driver');
      const res = await api(app)
        .post('/v1/driver/online')
        .set(bearer(pending.token))
        .send({ lat: CP.lat, lng: CP.lng })
        .expect(403);
      expect(res.body.error.code).toBe('NOT_ELIGIBLE');
    });

    it('location while offline returns 409 DRIVER_OFFLINE so the app re-onlines', async () => {
      const d = await approvedDriver(app, admin);
      const res = await api(app)
        .post('/v1/driver/location')
        .set(bearer(d.token))
        .send({ lat: CP.lat, lng: CP.lng })
        .expect(409);
      expect(res.body.error.code).toBe('DRIVER_OFFLINE');
    });

    it('nearby shows idle drivers with anonymised ids', async () => {
      const d = await onlineDriver(NEAR_CP);
      const rider = await loginAs(app, 'rider');
      const res = await api(app)
        .get(`/v1/drivers/nearby?lat=${CP.lat}&lng=${CP.lng}`)
        .set(bearer(rider.token))
        .expect(200);
      expect(res.body.length).toBeGreaterThanOrEqual(1);
      expect(res.body.length).toBeLessThanOrEqual(10);
      expect(res.body.map((x: Json) => x.driver_id)).not.toContain(d.id);
      expect(res.body[0]).toEqual({
        driver_id: expect.any(String),
        lat: expect.any(Number),
        lng: expect.any(Number),
        heading: expect.any(Number),
        vehicle_type: 'sedan',
      });
      await goOffline(d);
    });

    it('a driver whose app dies is marked offline within the heartbeat window', async () => {
      const d = await approvedDriver(app, admin);
      await api(app).post('/v1/driver/online').set(bearer(d.token)).send(FARTHER_CP).expect(204);
      expect(await redis.get(`driver:${d.id}:state`)).toBe('idle');
      // No keepalive: TTL 3 s + sweep every 1 s.
      await sleep(5500);
      expect(await redis.get(`driver:${d.id}:state`)).toBe('offline');
      expect(await redis.zscore('drivers:geo', d.id)).toBeNull();
    });
  });

  describe('matching (broadcast rounds, D-055)', () => {
    // OFFER_BATCH_SIZE is 2 in .env.test: a round reaches the two nearest free drivers.
    let near: Awaited<ReturnType<typeof onlineDriver>>;
    let far: Awaited<ReturnType<typeof onlineDriver>>;
    // Farther from CP than FARTHER_CP (1.5 km north), still inside the 3 km radius.
    const THIRD = { lat: 28.6315, lng: 77.238 };

    beforeEach(async () => {
      near = await onlineDriver(NEAR_CP, 'Near Driver');
      far = await onlineDriver(FARTHER_CP, 'Far Driver');
    });

    afterEach(async () => {
      // Free both drivers for the next test (ignore 409 if a test left one on a trip).
      for (const d of [near, far]) await api(app).post('/v1/driver/offline').set(bearer(d.token));
    });

    const firstRound = () =>
      Promise.all([next<Json>(near.socket, 'ride:offer'), next<Json>(far.socket, 'ride:offer')]);

    it('offers the nearest drivers together; accept notifies the rider and withdraws the other offer', async () => {
      const rider = await loginAs(app, 'rider');
      const riderSocket = await socketFor(rider);
      const round = firstRound();
      const res = await requestRide(rider);
      expect(res.status).toBe(201);
      const rideId = res.body.id;
      expect(res.body).toMatchObject({
        status: 'REQUESTED',
        payment_method: 'cash',
        trip_otp: null,
      });

      const [o1, o2] = await round;
      expect(o1).toMatchObject({
        ride_id: rideId,
        drop_address: INDIA_GATE.address,
        pickup: { address: CP.address },
      });
      expect(o1.distance_to_pickup_m).toBeGreaterThan(300);
      expect(o1.distance_to_pickup_m).toBeLessThan(800);
      expect(o2.ride_id).toBe(rideId);
      expect(o2.distance_to_pickup_m).toBeGreaterThan(o1.distance_to_pickup_m);
      expect(o2.expires_at).toBe(o1.expires_at); // one round, one deadline
      expect(await redis.get(`driver:${near.id}:state`)).toBe('offered');

      // The farther driver taps Accept first: they win and the near driver's offer is withdrawn.
      const withdrawn = next<Json>(near.socket, 'ride:offer:expired');
      const accepted = next<Json>(riderSocket, 'ride:status', 5000, (p) => p.status === 'ACCEPTED');
      const ackRes = await far.socket.emitWithAck('driver:offer:accept', { ride_id: rideId });
      expect(ackRes).toMatchObject({ ok: true, data: { id: rideId, status: 'ACCEPTED' } });
      expect((await withdrawn).ride_id).toBe(rideId);

      const status = await accepted;
      expect(status.driver).toMatchObject({
        id: far.id,
        name: 'Far Driver',
        vehicle: { make: 'Maruti Suzuki' },
      });
      expect(status.driver.phone_masked).toMatch(/^\*+\d{4}$/);
      expect(status.driver.phone).toBeUndefined();
      expect(status.trip_otp).toMatch(/^\d{4}$/);

      const offers = await prisma.rideOffer.findMany({
        where: { rideId },
        orderBy: { distanceToPickupM: 'asc' },
      });
      expect(offers.map((o) => [o.driverId, o.response])).toEqual([
        [near.id, 'withdrawn'],
        [far.id, 'accepted'],
      ]);
      expect(await redis.get(`driver:${far.id}:state`)).toBe('on_trip');
      expect(await redis.get(`driver:${near.id}:state`)).toBe('idle');
      expect(await redis.exists(`ride:${rideId}:offers`)).toBe(0);

      // Driver on a trip cannot go offline.
      const off = await api(app).post('/v1/driver/offline').set(bearer(far.token)).expect(409);
      expect(off.body.error.code).toBe('ON_TRIP');

      // The rider cannot book a second ride meanwhile.
      const second = await requestRide(rider);
      expect(second.status).toBe(409);
      expect(second.body.error.code).toBe('ACTIVE_RIDE_EXISTS');

      // Active ride endpoints.
      const active = await api(app).get('/v1/rides/active').set(bearer(rider.token)).expect(200);
      expect(active.body).toMatchObject({ id: rideId, status: 'ACCEPTED' });
      const driverActive = await api(app)
        .get('/v1/driver/rides/active')
        .set(bearer(far.token))
        .expect(200);
      expect(driverActive.body.rider.phone_masked).toMatch(/^\*+\d{4}$/);
      expect(driverActive.body.rider.phone).toBeUndefined();

      // Rider sees the car move within 2 s of movement, with an ETA to pickup.
      const moved = { lat: 28.64, lng: 77.2167 };
      const pos = next<Json>(riderSocket, 'driver:position', 2000, (p) => p.lat === moved.lat);
      const t0 = Date.now();
      far.socket.emit('driver:location', { ...moved, heading: 180, speed: 8, accuracy: 5 });
      const p = await pos;
      expect(Date.now() - t0).toBeLessThan(2000);
      expect(p).toMatchObject({ ride_id: rideId, driver_id: far.id, heading: 180 });
      expect(p.eta_s).toBeGreaterThan(0);

      // Reconnecting driver gets the active ride re-sent.
      const again = await connectSocket(app, far.token);
      sockets.push(again);
      const resent = await next<Json>(again, 'ride:status', 3000);
      expect(resent).toMatchObject({ ride_id: rideId, status: 'ACCEPTED' });
    });

    it('an ignored round expires for everyone; the next round asks drivers not offered yet', async () => {
      const third = await onlineDriver(THIRD, 'Third Driver');
      try {
        const rider = await loginAs(app, 'rider');
        const round = firstRound();
        const rideId = (await requestRide(rider)).body.id;
        await round;
        const expiredNear = next<Json>(near.socket, 'ride:offer:expired', 10_000);
        const expiredFar = next<Json>(far.socket, 'ride:offer:expired', 10_000);
        // Nobody answers → after OFFER_TIMEOUT_SECONDS the round closes and the third driver is asked.
        const o3 = await next<Json>(third.socket, 'ride:offer', 10_000);
        expect(o3.ride_id).toBe(rideId);
        expect((await expiredNear).ride_id).toBe(rideId);
        expect((await expiredFar).ride_id).toBe(rideId);
        const byDriver = (rows: { driverId: string; response: string | null }[]) =>
          rows.map((o) => [o.driverId, o.response]).sort((x, y) => x[0]!.localeCompare(y[0]!));
        expect(byDriver(await prisma.rideOffer.findMany({ where: { rideId } }))).toEqual(
          byDriver([
            { driverId: near.id, response: 'timeout' },
            { driverId: far.id, response: 'timeout' },
            { driverId: third.id, response: null },
          ]),
        );
        // A reconnecting driver gets every open offer re-sent.
        const again = await connectSocket(app, third.token);
        sockets.push(again);
        expect((await next<Json>(again, 'ride:offer', 3000)).ride_id).toBe(rideId);

        const gone = next<Json>(third.socket, 'ride:offer:expired');
        await api(app)
          .post(`/v1/rides/${rideId}/cancel`)
          .set(bearer(rider.token))
          .send({})
          .expect(200);
        expect((await gone).ride_id).toBe(rideId);
      } finally {
        await goOffline(third);
      }
    }, 20_000);

    it('simultaneous accepts: exactly one wins', async () => {
      const rider = await loginAs(app, 'rider');
      const round = firstRound();
      const rideId = (await requestRide(rider)).body.id;
      await round;

      const results = await Promise.all([
        api(app).post(`/v1/driver/rides/${rideId}/accept`).set(bearer(near.token)),
        api(app).post(`/v1/driver/rides/${rideId}/accept`).set(bearer(far.token)),
        near.socket.emitWithAck('driver:offer:accept', { ride_id: rideId }),
      ]);
      const [restNear, restFar, wsNear] = results;
      const wins = [restNear.status === 200, restFar.status === 200, wsNear.ok === true].filter(
        Boolean,
      );
      expect(wins).toHaveLength(1);

      const ride = await prisma.ride.findUniqueOrThrow({ where: { id: rideId } });
      expect(ride.status).toBe('ACCEPTED');
      expect([near.id, far.id]).toContain(ride.driverId);
      const loser = ride.driverId === far.id ? restNear : restFar;
      expect(loser.status).toBe(409);
      expect(loser.body.error.code).toBe('OFFER_NOT_VALID');
      expect(await prisma.rideEvent.count({ where: { rideId, toStatus: 'ACCEPTED' } })).toBe(1);
      const responses = (await prisma.rideOffer.findMany({ where: { rideId } }))
        .map((o) => o.response)
        .sort();
      expect(responses).toEqual(['accepted', 'withdrawn']);
    });

    it('one reject keeps the round open; once everyone has answered the next round starts at once', async () => {
      const third = await onlineDriver(THIRD, 'Third Driver');
      try {
        const rider = await loginAs(app, 'rider');
        const round = firstRound();
        const rideId = (await requestRide(rider)).body.id;
        await round;
        const thirdOffer = next<Json>(third.socket, 'ride:offer', 2500); // < OFFER_TIMEOUT_SECONDS
        await api(app).post(`/v1/driver/rides/${rideId}/reject`).set(bearer(near.token)).expect(204);
        // Answering twice is invalid; the far driver is still deciding.
        await api(app).post(`/v1/driver/rides/${rideId}/reject`).set(bearer(near.token)).expect(409);
        expect(await redis.hkeys(`ride:${rideId}:offers`)).toEqual([far.id]);
        await api(app).post(`/v1/driver/rides/${rideId}/reject`).set(bearer(far.token)).expect(204);
        expect((await thirdOffer).ride_id).toBe(rideId);
        expect(await redis.get(`driver:${near.id}:state`)).toBe('idle');
        await api(app)
          .post(`/v1/rides/${rideId}/cancel`)
          .set(bearer(rider.token))
          .send({})
          .expect(200);
      } finally {
        await goOffline(third);
      }
    });

    it('a request for an auto only reaches auto drivers (D-056)', async () => {
      const auto = await onlineDriver(THIRD, 'Auto Driver', 'auto');
      try {
        const rider = await loginAs(app, 'rider');
        const est = await estimate(rider);
        const option = est.options.find((o: Json) => o.vehicle_type === 'auto');
        const body = { pickup: CP, drop: INDIA_GATE, payment_method: 'cash', vehicle_type: 'auto' };
        // The fare config must belong to the requested class.
        const bad = await api(app)
          .post('/v1/rides')
          .set(bearer(rider.token))
          .send({ ...body, fare_config_id: est.fare_config_id });
        expect(bad.status).toBe(422);
        expect(bad.body.error.code).toBe('FARE_CONFIG_INVALID');

        const sedanOffer = next<Json>(near.socket, 'ride:offer', 2500).then(
          () => 'offered',
          () => 'none',
        );
        const autoOffer = next<Json>(auto.socket, 'ride:offer', 5000);
        const res = await api(app)
          .post('/v1/rides')
          .set(bearer(rider.token))
          .send({ ...body, fare_config_id: option.fare_config_id });
        expect(res.status).toBe(201);
        expect(res.body.vehicle_type).toBe('auto');
        expect((await autoOffer).ride_id).toBe(res.body.id);
        expect(await sedanOffer).toBe('none'); // the nearer sedan driver is never asked
        await api(app)
          .post(`/v1/rides/${res.body.id}/cancel`)
          .set(bearer(rider.token))
          .send({})
          .expect(200);
      } finally {
        await goOffline(auto);
      }
    });

    it('going offline answers open offers as rejected', async () => {
      const rider = await loginAs(app, 'rider');
      const round = firstRound();
      const rideId = (await requestRide(rider)).body.id;
      await round;
      await goOffline(near);
      const row = await prisma.rideOffer.findFirstOrThrow({ where: { rideId, driverId: near.id } });
      expect(row.response).toBe('rejected');
      expect(await redis.hkeys(`ride:${rideId}:offers`)).toEqual([far.id]);
      await api(app)
        .post(`/v1/rides/${rideId}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
    });

    it('rider cancel while searching withdraws every offer and frees the drivers', async () => {
      const rider = await loginAs(app, 'rider');
      const round = firstRound();
      const rideId = (await requestRide(rider)).body.id;
      await round;
      const expiredNear = next<Json>(near.socket, 'ride:offer:expired');
      const expiredFar = next<Json>(far.socket, 'ride:offer:expired');
      const res = await api(app)
        .post(`/v1/rides/${rideId}/cancel`)
        .set(bearer(rider.token))
        .send({ reason: 'Changed plans' })
        .expect(200);
      expect(res.body).toMatchObject({
        status: 'CANCELLED',
        cancelled_by: 'rider',
        cancellation_fee: 0,
      });
      expect((await expiredNear).ride_id).toBe(rideId);
      expect((await expiredFar).ride_id).toBe(rideId);
      expect(await redis.get(`driver:${near.id}:state`)).toBe('idle');
      expect(await redis.get(`driver:${far.id}:state`)).toBe('idle');
      await sleep(4000); // past the round timeout: nobody else is offered a cancelled ride
      const rows = await prisma.rideOffer.findMany({ where: { rideId } });
      expect(rows.map((o) => o.response)).toEqual(['withdrawn', 'withdrawn']);
    });
  });

  describe('no driver', () => {
    it('ends in NO_DRIVER and notifies the rider when nobody is nearby', async () => {
      const rider = await loginAs(app, 'rider');
      const socket = await socketFor(rider);
      const noDriver = next<Json>(socket, 'ride:no_driver', 20_000);
      const res = await requestRide(rider, GREATER_NOIDA, CP);
      expect(res.status).toBe(201);
      expect((await noDriver).ride_id).toBe(res.body.id);
      const ride = await prisma.ride.findUniqueOrThrow({ where: { id: res.body.id } });
      expect(ride.status).toBe('NO_DRIVER');
      // A NO_DRIVER ride does not block a new request.
      const again = await requestRide(rider, GREATER_NOIDA, CP);
      expect(again.status).toBe(201);
      await api(app)
        .post(`/v1/rides/${again.body.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
    }, 30_000);

    it('stops after MAX_OFFER_ROUNDS_PER_RIDE rounds of unanswered offers', async () => {
      // Six free drivers near CP, two per round, three rounds, nobody answers.
      const drivers = [];
      for (const pos of [
        NEAR_CP,
        FARTHER_CP,
        { lat: 28.64, lng: 77.22 },
        { lat: 28.628, lng: 77.21 },
        { lat: 28.636, lng: 77.226 },
        { lat: 28.624, lng: 77.214 },
      ])
        drivers.push(await onlineDriver(pos));
      const rider = await loginAs(app, 'rider');
      const socket = await socketFor(rider);
      const noDriver = next<Json>(socket, 'ride:no_driver', 20_000);
      const rideId = (await requestRide(rider)).body.id;
      await noDriver;
      const rows = await prisma.rideOffer.findMany({ where: { rideId } });
      expect(rows).toHaveLength(6);
      expect(new Set(rows.map((o) => o.driverId)).size).toBe(6);
      expect(new Set(rows.map((o) => o.response))).toEqual(new Set(['timeout']));
      for (const d of drivers) await goOffline(d);
    }, 30_000);
  });

  describe('websocket auth', () => {
    it('refuses a connection without a valid token', async () => {
      await expect(connectSocket(app, 'garbage')).rejects.toThrow('UNAUTHORIZED');
    });

    it('rejects driver events from a rider socket', async () => {
      const rider = await loginAs(app, 'rider');
      const socket = await socketFor(rider);
      const res = await socket.emitWithAck('driver:location', { lat: CP.lat, lng: CP.lng });
      expect(res).toEqual({
        ok: false,
        error: { code: 'FORBIDDEN', message: 'Not allowed for this role' },
      });
    });

    it('validates websocket payloads', async () => {
      const d = await onlineDriver(NEAR_CP);
      const res = await d.socket.emitWithAck('driver:location', { lat: 999, lng: 'x' });
      expect(res.ok).toBe(false);
      expect(res.error.code).toBe('VALIDATION_FAILED');
      await goOffline(d);
    });
  });
});
