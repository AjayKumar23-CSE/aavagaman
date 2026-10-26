/**
 * SPEC §20 Phase 3 acceptance, API level (timers shortened in .env.test:
 * free-cancel window 2 s, no-show wait 2 s, OTP SMS fallback 1 s):
 * trips complete with fares within the cap; wrong OTP blocked; rider cancel after
 * the window carries a fee onto the next ride; three driver cancels suspend the
 * driver and alert admin; share link shows live position; SOS reaches admins.
 */
import { NestExpressApplication } from '@nestjs/platform-express';
import type { Socket } from 'socket.io-client';
import { PrismaService } from '../../src/common/prisma.service';
import { RedisService } from '../../src/common/redis.service';
import { PushService } from '../../src/modules/notifications/push.service';
import { SmsService } from '../../src/modules/notifications/sms.service';
import { api, connectSocket, createTestApp, next, sleep } from './app';
import {
  adminLogin,
  approvedDriver,
  bearer,
  CP,
  FARTHER_CP,
  INDIA_GATE,
  loginAs,
  NEAR_CP,
  Session,
} from './fixtures';

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

/** ~35 m east of CP: inside the 300 m arrival radius. */
const AT_PICKUP = { lat: CP.lat, lng: CP.lng + 0.00036 };

describe('Phase 3: trip lifecycle, fares, cancellations, ratings (e2e)', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;
  let redis: RedisService;
  let admin: string;
  let adminSocket: Socket;
  const sockets: Socket[] = [];
  const keepalives: NodeJS.Timeout[] = [];

  beforeAll(async () => {
    app = await createTestApp({ worker: true });
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);
    admin = await adminLogin(app);
    adminSocket = await connectSocket(app, admin);
    sockets.push(adminSocket);
  });

  afterEach(() => {
    keepalives.splice(0).forEach(clearInterval);
  });

  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    await app?.close();
  });

  type Driver = Session & { socket: Socket };

  const socketFor = async (s: Session) => {
    const sock = await connectSocket(app, s.token);
    sockets.push(sock);
    return sock;
  };

  const onlineDriver = async (
    pos: { lat: number; lng: number } = NEAR_CP,
    name = 'Trip Driver',
  ): Promise<Driver> => {
    const d = await approvedDriver(app, admin, name);
    await api(app).post('/v1/driver/online').set(bearer(d.token)).send(pos).expect(204);
    const socket = await socketFor(d);
    keepalives.push(
      setInterval(
        () => socket.emit('driver:location', { ...pos, heading: 0, speed: 0, accuracy: 5 }),
        1000,
      ),
    );
    return { ...d, socket };
  };

  const offline = (d: Session) => api(app).post('/v1/driver/offline').set(bearer(d.token));

  const bookAndAccept = async (
    rider: Session,
    driver: Driver,
    pickup = CP,
    drop = INDIA_GATE,
  ): Promise<Json> => {
    const est = (
      await api(app)
        .post('/v1/fare/estimate')
        .set(bearer(rider.token))
        .send({ pickup, drop })
        .expect(200)
    ).body;
    const offer = next<Json>(driver.socket, 'ride:offer', 10_000);
    const ride = (
      await api(app)
        .post('/v1/rides')
        .set(bearer(rider.token))
        .send({ pickup, drop, fare_config_id: est.fare_config_id, payment_method: 'cash' })
        .expect(201)
    ).body;
    expect((await offer).ride_id).toBe(ride.id);
    const accepted = await api(app)
      .post(`/v1/driver/rides/${ride.id}/accept`)
      .set(bearer(driver.token))
      .expect(200);
    return { ...accepted.body, _estimate: est };
  };

  const driverPost = (d: Session, rideId: string, action: string, body: object = {}) =>
    api(app).post(`/v1/driver/rides/${rideId}/${action}`).set(bearer(d.token)).send(body);

  const stateOf = (d: Session) => redis.get(`driver:${d.id}:state`);

  describe('happy path', () => {
    it('ACCEPTED → ARRIVED (distance check) → STARTED (OTP) → COMPLETED (fare within cap) → PAID (cash) → ratings, receipt, history', async () => {
      const rider = await loginAs(app, 'rider');
      const riderSocket = await socketFor(rider);
      const driver = await onlineDriver();
      const pushSpy = jest.spyOn(app.get(PushService), 'toUser');
      const ride = await bookAndAccept(rider, driver);
      const rideId = ride.id as string;
      const estFare = ride._estimate as Json;

      // Rider: OTP visible after acceptance; driver: not.
      const riderView = (
        await api(app).get('/v1/rides/active').set(bearer(rider.token)).expect(200)
      ).body;
      expect(riderView.trip_otp).toMatch(/^\d{4}$/);
      expect(ride.trip_otp).toBeUndefined();
      expect(ride.rider.phone).toBeUndefined();
      const otp = riderView.trip_otp as string;

      // "Your driver is nearby" once, when the driver comes within 300 m while ACCEPTED.
      driver.socket.emit('driver:location', { ...AT_PICKUP, heading: 90, speed: 3, accuracy: 5 });
      driver.socket.emit('driver:location', { ...AT_PICKUP, heading: 90, speed: 3, accuracy: 5 });
      await sleep(300);
      const nearby = pushSpy.mock.calls.filter(
        ([uid, m]) => uid === rider.id && m.title === 'Your driver is nearby',
      );
      expect(nearby).toHaveLength(1);

      // Arrived: too far (1.5 km) → 422; at the pickup → ARRIVED, OTP pushed. With masked
      // calling on (.env.test) the number stays hidden and the bridge number is advertised.
      const far = await driverPost(driver, rideId, 'arrived', FARTHER_CP).expect(422);
      expect(far.body.error.code).toBe('TOO_FAR_FROM_PICKUP');
      const arrivedEvent = next<Json>(
        riderSocket,
        'ride:status',
        5000,
        (p) => p.status === 'ARRIVED',
      );
      const arrived = await driverPost(driver, rideId, 'arrived', AT_PICKUP).expect(200);
      expect(arrived.body.status).toBe('ARRIVED');
      expect(arrived.body.rider.phone).toBeUndefined();
      expect(arrived.body.rider.call_via).toBe('+911140001234');
      expect((await arrivedEvent).trip_otp).toBe(otp);
      expect(
        pushSpy.mock.calls.some(([uid, m]) => uid === rider.id && m.body.includes(`OTP: ${otp}`)),
      ).toBe(true);

      // Start: wrong OTP → 401 with attempts left; right OTP → STARTED.
      const wrongOtp = otp === '0000' ? '0001' : '0000';
      const wrong = await driverPost(driver, rideId, 'start', {
        otp: wrongOtp,
        ...AT_PICKUP,
      }).expect(401);
      expect(wrong.body.error).toMatchObject({
        code: 'OTP_INVALID',
        message: expect.stringContaining('2 attempts left'),
      });
      const startedEvent = next<Json>(
        riderSocket,
        'ride:status',
        5000,
        (p) => p.status === 'STARTED',
      );
      const started = await driverPost(driver, rideId, 'start', { otp, ...AT_PICKUP }).expect(200);
      expect(started.body.status).toBe('STARTED');
      await startedEvent;

      // Zig-zag track (~35 m legs, 1 s apart): track distance ≈ 140 m, straight-line ≈ 0.
      const legs = [0.00036, 0, 0.00036, 0];
      for (const dLng of legs) {
        await sleep(1000);
        driver.socket.emit('driver:location', {
          lat: CP.lat,
          lng: CP.lng + dLng,
          heading: 90,
          speed: 30,
          accuracy: 8,
        });
      }
      await sleep(400);

      const completedEvent = next<Json>(
        riderSocket,
        'ride:status',
        5000,
        (p) => p.status === 'COMPLETED',
      );
      const completed = await driverPost(driver, rideId, 'complete', {
        lat: CP.lat,
        lng: CP.lng,
      }).expect(200);
      expect(completed.body.status).toBe('COMPLETED');
      expect(completed.body.actual_distance_m).toBeGreaterThan(100);
      expect(completed.body.actual_distance_m).toBeLessThan(220);
      expect(completed.body.final_fare).toBe(80); // min fare
      expect(completed.body.final_fare).toBeLessThanOrEqual(estFare.fare_max * 1.25);
      expect(completed.body.amount_due).toBe(80);
      expect((await completedEvent).final_fare).toBe(80);
      expect(
        pushSpy.mock.calls.some(([uid, m]) => uid === driver.id && m.body === 'Collect INR 80'),
      ).toBe(true);

      // Receipt reconciles with final_fare (GST-inclusive).
      const receipt = (
        await api(app).get(`/v1/rides/${rideId}/receipt`).set(bearer(rider.token)).expect(200)
      ).body;
      expect(receipt).toMatchObject({
        fare: 80,
        total: 80,
        cancellation_fee: 0,
        payment_status: 'pending',
        currency: 'INR',
      });
      expect(receipt.gst).toBeCloseTo(3.81, 2);
      expect(receipt.components.min_fare_applied).toBe(true);
      expect(receipt.components.base_fare).toBe(50);

      // Cash collected → PAID, payment row, driver idle, payment:status to both.
      const payRider = next<Json>(riderSocket, 'payment:status', 5000);
      const payDriver = next<Json>(driver.socket, 'payment:status', 5000);
      const paid = await driverPost(driver, rideId, 'cash-collected').expect(200);
      expect(paid.body.status).toBe('PAID');
      expect(await payRider).toEqual({ ride_id: rideId, status: 'paid', method: 'cash' });
      expect(await payDriver).toEqual({ ride_id: rideId, status: 'paid', method: 'cash' });
      const payment = await prisma.payment.findUniqueOrThrow({ where: { rideId } });
      expect(payment).toMatchObject({ method: 'cash', status: 'paid' });
      expect(Number(payment.amount)).toBe(80);
      expect(await stateOf(driver)).toBe('idle');
      await driverPost(driver, rideId, 'cash-collected').expect(409);

      // Ratings both ways, once each.
      await api(app)
        .post(`/v1/rides/${rideId}/rating`)
        .set(bearer(rider.token))
        .send({ stars: 5, comment: 'Smooth' })
        .expect(201);
      await api(app)
        .post(`/v1/driver/rides/${rideId}/rating`)
        .set(bearer(driver.token))
        .send({ stars: 4 })
        .expect(201);
      const again = await api(app)
        .post(`/v1/rides/${rideId}/rating`)
        .set(bearer(rider.token))
        .send({ stars: 1 })
        .expect(409);
      expect(again.body.error.code).toBe('ALREADY_RATED');
      const driverUser = await prisma.user.findUniqueOrThrow({ where: { id: driver.id } });
      const riderUser = await prisma.user.findUniqueOrThrow({ where: { id: rider.id } });
      expect([Number(driverUser.ratingAvg), driverUser.ratingCount]).toEqual([5, 1]);
      expect([Number(riderUser.ratingAvg), riderUser.ratingCount]).toEqual([4, 1]);

      // History for both parties; events recorded for every transition.
      const riderHistory = (
        await api(app).get('/v1/rides?limit=5').set(bearer(rider.token)).expect(200)
      ).body;
      expect(riderHistory.data.map((r: Json) => r.id)).toContain(rideId);
      const driverHistory = (
        await api(app).get('/v1/driver/rides').set(bearer(driver.token)).expect(200)
      ).body;
      expect(driverHistory.data[0]).toMatchObject({ id: rideId, status: 'PAID' });
      // Per-trip split for the Earnings list: commission on the fare ex-GST.
      const e = driverHistory.data[0].earning;
      expect(e.fare).toBe(driverHistory.data[0].final_fare);
      expect(e.net).toBeCloseTo(e.fare - e.commission - e.gst, 2);
      expect(e.commission).toBeGreaterThan(0);
      const events = await prisma.rideEvent.findMany({ where: { rideId }, orderBy: { id: 'asc' } });
      expect(events.map((e) => e.toStatus)).toEqual([
        'REQUESTED',
        'ACCEPTED',
        'ARRIVED',
        'ARRIVED',
        'STARTED',
        'COMPLETED',
        'PAID',
      ]);
      expect(events[3].meta).toMatchObject({ type: 'otp_failed', attempts: 1, flagged: false });

      pushSpy.mockRestore();
      await offline(driver).expect(204);
    }, 40_000);
  });

  describe('rider cancellation fees (SPEC §9.5)', () => {
    it('free inside the window, fee after it, and the fee rides along on the next completed trip', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();

      // Within the (2 s) window: no fee, driver back to idle and told.
      const r1 = await bookAndAccept(rider, driver);
      const cancelledEvent = next<Json>(
        driver.socket,
        'ride:status',
        5000,
        (p) => p.status === 'CANCELLED',
      );
      const c1 = await api(app)
        .post(`/v1/rides/${r1.id}/cancel`)
        .set(bearer(rider.token))
        .send({ reason: 'Oops' })
        .expect(200);
      expect(c1.body).toMatchObject({
        status: 'CANCELLED',
        cancelled_by: 'rider',
        cancellation_fee: 0,
      });
      expect((await cancelledEvent).ride_id).toBe(r1.id);
      expect(await stateOf(driver)).toBe('idle');

      // After the window: the configured fee.
      const r2 = await bookAndAccept(rider, driver);
      await sleep(2300);
      const c2 = await api(app)
        .post(`/v1/rides/${r2.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
      expect(c2.body.cancellation_fee).toBe(30);
      expect(await stateOf(driver)).toBe('idle');

      // Rating a cancelled ride is refused.
      const noRate = await api(app)
        .post(`/v1/rides/${r2.id}/rating`)
        .set(bearer(rider.token))
        .send({ stars: 3 })
        .expect(409);
      expect(noRate.body.error.code).toBe('RIDE_NOT_RATEABLE');

      // Next completed ride carries the fee as a line item.
      const r3 = await bookAndAccept(rider, driver);
      const pending = await api(app)
        .get(`/v1/rides/${r3.id}/receipt`)
        .set(bearer(rider.token))
        .expect(409);
      expect(pending.body.error.code).toBe('RECEIPT_NOT_READY');
      await driverPost(driver, r3.id, 'arrived', AT_PICKUP).expect(200);
      const otp = (await api(app).get(`/v1/rides/${r3.id}`).set(bearer(rider.token)).expect(200))
        .body.trip_otp;
      await driverPost(driver, r3.id, 'start', { otp, ...AT_PICKUP }).expect(200);
      const done = await driverPost(driver, r3.id, 'complete', {
        lat: INDIA_GATE.lat,
        lng: INDIA_GATE.lng,
      }).expect(200);
      expect(done.body.cancellation_fee).toBe(30);
      expect(done.body.amount_due).toBe(done.body.final_fare + 30);
      expect(done.body.final_fare).toBeGreaterThanOrEqual(80);
      const receipt = (
        await api(app).get(`/v1/rides/${r3.id}/receipt`).set(bearer(rider.token)).expect(200)
      ).body;
      expect(receipt.total).toBe(receipt.fare + 30);
      expect(
        (await prisma.ride.findUniqueOrThrow({ where: { id: r2.id } })).feeAppliedToRideId,
      ).toBe(r3.id);
      // Applied once: a further ride owes nothing extra.
      const paid = await driverPost(driver, r3.id, 'cash-collected').expect(200);
      expect(
        Number((await prisma.payment.findUniqueOrThrow({ where: { rideId: r3.id } })).amount),
      ).toBe(paid.body.amount_due);
      await offline(driver).expect(204);
    }, 40_000);
  });

  describe('driver cancellation (SPEC §9.5)', () => {
    it('re-queues the ride excluding that driver, counts against them, and suspends at 3', async () => {
      const rider = await loginAs(app, 'rider');
      const riderSocket = await socketFor(rider);
      const a = await onlineDriver(NEAR_CP, 'Driver A');
      const b = await onlineDriver(FARTHER_CP, 'Driver B');

      const ride = await bookAndAccept(rider, a);
      const requeued = next<Json>(
        riderSocket,
        'ride:status',
        5000,
        (p) => p.status === 'REQUESTED',
      );
      const offerB = next<Json>(b.socket, 'ride:offer', 10_000);
      const cancel = await driverPost(a, ride.id, 'cancel', { reason: 'Vehicle breakdown' }).expect(
        200,
      );
      expect(cancel.body.status).toBe('REQUESTED');
      expect(cancel.body.driver).toBeNull();
      await requeued;
      expect((await offerB).ride_id).toBe(ride.id);
      expect(await stateOf(a)).toBe('idle');
      expect(
        (await prisma.driver.findUniqueOrThrow({ where: { userId: a.id } })).cancelCountToday,
      ).toBe(1);

      await driverPost(b, ride.id, 'accept').expect(200);
      expect((await prisma.ride.findUniqueOrThrow({ where: { id: ride.id } })).driverId).toBe(b.id);
      await api(app)
        .post(`/v1/rides/${ride.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
      await offline(b).expect(204);

      // Two more cancellations today → suspended, offline, admin alerted.
      const alert = next<Json>(
        adminSocket,
        'admin:alert',
        15_000,
        (p) => p.type === 'driver_suspended' && p.driver_id === a.id,
      );
      for (let i = 0; i < 2; i++) {
        const r = await bookAndAccept(rider, a);
        await driverPost(a, r.id, 'cancel', { reason: 'Changed my mind' }).expect(200);
        await api(app)
          .post(`/v1/rides/${r.id}/cancel`)
          .set(bearer(rider.token))
          .send({})
          .expect(200);
      }
      expect((await alert).ride_id).toBeDefined();
      const row = await prisma.driver.findUniqueOrThrow({ where: { userId: a.id } });
      expect(row).toMatchObject({ verificationStatus: 'suspended', cancelCountToday: 3 });
      expect(await stateOf(a)).toBe('offline');
      const online = await api(app)
        .post('/v1/driver/online')
        .set(bearer(a.token))
        .send(NEAR_CP)
        .expect(403);
      expect(online.body.error.code).toBe('NOT_ELIGIBLE');
    }, 60_000);

    it('rider no-show: driver cancels after waiting → fee to rider, not counted against the driver', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const ride = await bookAndAccept(rider, driver);
      await driverPost(driver, ride.id, 'arrived', AT_PICKUP).expect(200);
      await sleep(2300);
      const res = await driverPost(driver, ride.id, 'cancel', {
        reason: 'Rider did not show up',
      }).expect(200);
      expect(res.body).toMatchObject({
        status: 'CANCELLED',
        cancelled_by: 'driver',
        cancellation_fee: 30,
      });
      expect(
        (await prisma.driver.findUniqueOrThrow({ where: { userId: driver.id } }))
          .cancelCountToday ?? 0,
      ).toBe(0);
      expect(await stateOf(driver)).toBe('idle');
      await offline(driver).expect(204);
    }, 30_000);

    it('requires a reason', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const ride = await bookAndAccept(rider, driver);
      await driverPost(driver, ride.id, 'cancel', {}).expect(400);
      await api(app)
        .post(`/v1/rides/${ride.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
      await offline(driver).expect(204);
    }, 30_000);
  });

  describe('trip OTP (SPEC §9.6)', () => {
    it('locks after 3 wrong attempts, alerts admin, and the driver may still cancel', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const ride = await bookAndAccept(rider, driver);
      await driverPost(driver, ride.id, 'arrived', AT_PICKUP).expect(200);
      const otp = (await api(app).get(`/v1/rides/${ride.id}`).set(bearer(rider.token)).expect(200))
        .body.trip_otp;
      const wrong = otp === '1111' ? '2222' : '1111';
      const alert = next<Json>(
        adminSocket,
        'admin:alert',
        5000,
        (p) => p.type === 'otp_failed' && p.ride_id === ride.id,
      );
      for (let i = 0; i < 3; i++)
        await driverPost(driver, ride.id, 'start', { otp: wrong, ...AT_PICKUP }).expect(401);
      expect((await alert).attempts).toBe(3);
      const locked = await driverPost(driver, ride.id, 'start', { otp, ...AT_PICKUP }).expect(401);
      expect(locked.body.error.code).toBe('OTP_LOCKED');
      expect((await prisma.ride.findUniqueOrThrow({ where: { id: ride.id } })).otpAttempts).toBe(3);
      await driverPost(driver, ride.id, 'cancel', { reason: 'Could not verify rider' }).expect(200);
      await api(app).post(`/v1/rides/${ride.id}/cancel`).set(bearer(rider.token)).send({});
      await offline(driver);
    }, 30_000);

    it('SMS fallback: the OTP is texted only if the rider stays offline after ARRIVED', async () => {
      const smsSpy = jest.spyOn(app.get(SmsService), 'sendOtp').mockResolvedValue();
      const driver = await onlineDriver();

      const offlineRider = await loginAs(app, 'rider');
      const r1 = await bookAndAccept(offlineRider, driver); // rider never opened a socket
      await driverPost(driver, r1.id, 'arrived', AT_PICKUP).expect(200);
      await sleep(2500);
      const riderPhone = (await prisma.user.findUniqueOrThrow({ where: { id: offlineRider.id } }))
        .phone;
      const otp = (await prisma.ride.findUniqueOrThrow({ where: { id: r1.id } })).tripOtp;
      expect(smsSpy).toHaveBeenCalledWith(riderPhone, otp);
      await api(app)
        .post(`/v1/rides/${r1.id}/cancel`)
        .set(bearer(offlineRider.token))
        .send({})
        .expect(200);

      const onlineRider = await loginAs(app, 'rider');
      await socketFor(onlineRider);
      const r2 = await bookAndAccept(onlineRider, driver);
      smsSpy.mockClear(); // drop the 6-digit login OTP sent by loginAs
      await driverPost(driver, r2.id, 'arrived', AT_PICKUP).expect(200);
      await sleep(2500);
      expect(smsSpy).not.toHaveBeenCalled();
      await api(app)
        .post(`/v1/rides/${r2.id}/cancel`)
        .set(bearer(onlineRider.token))
        .send({})
        .expect(200);
      smsSpy.mockRestore();
      await offline(driver).expect(204);
    }, 40_000);
  });

  describe('share link and SOS', () => {
    it('GET /share/:token is public JSON (or an HTML page for browsers) with the live position', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const ride = await bookAndAccept(rider, driver);
      const token = (
        await api(app).get(`/v1/rides/${ride.id}`).set(bearer(rider.token)).expect(200)
      ).body.share_token;
      expect(token).toHaveLength(32);
      await sleep(1200); // one keepalive fix after acceptance

      const json = await api(app)
        .get(`/v1/share/${token}`)
        .set('Accept', 'application/json')
        .expect(200);
      expect(json.body).toMatchObject({
        status: 'ACCEPTED',
        driver_name: 'Trip Driver',
        vehicle: { make: 'Maruti Suzuki' },
        pickup: { address: CP.address },
      });
      expect(json.body.current_location).toMatchObject({ lat: NEAR_CP.lat, lng: NEAR_CP.lng });
      expect(JSON.stringify(json.body)).not.toMatch(/\+91\d{10}/);

      const html = await api(app)
        .get(`/v1/share/${token}`)
        .set('Accept', 'text/html,application/xhtml+xml')
        .expect(200);
      expect(html.headers['content-type']).toMatch(/text\/html/);
      expect(html.headers['content-security-policy']).toMatch(/script-src 'nonce-/);
      expect(html.text).toContain('Live trip');
      expect(html.text).toContain(`/v1/share/${token}`);

      await api(app).get('/v1/share/nope').set('Accept', 'application/json').expect(404);
      await api(app)
        .post(`/v1/rides/${ride.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
      await offline(driver).expect(204);
    }, 30_000);

    it('SOS from rider or driver is recorded and alerts admins', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const ride = await bookAndAccept(rider, driver);
      const smsSpy = jest.spyOn(app.get(SmsService), 'sendAlert').mockResolvedValue();

      const alert = next<Json>(adminSocket, 'sos:alert', 5000, (p) => p.ride_id === ride.id);
      const res = await api(app)
        .post(`/v1/rides/${ride.id}/sos`)
        .set(bearer(rider.token))
        .send({ lat: CP.lat, lng: CP.lng })
        .expect(201);
      expect(res.body.id).toBeDefined();
      expect(await alert).toMatchObject({
        ride_id: ride.id,
        user_id: rider.id,
        role: 'rider',
        lat: CP.lat,
        lng: CP.lng,
      });
      await api(app)
        .post(`/v1/rides/${ride.id}/sos`)
        .set(bearer(driver.token))
        .send(NEAR_CP)
        .expect(201);
      const stranger = await loginAs(app, 'rider');
      await api(app)
        .post(`/v1/rides/${ride.id}/sos`)
        .set(bearer(stranger.token))
        .send(NEAR_CP)
        .expect(404);
      await sleep(200);
      expect(await prisma.sosAlert.count({ where: { rideId: ride.id } })).toBe(2);
      expect(smsSpy).toHaveBeenCalledWith(
        '+910000000000',
        expect.stringContaining('SOS from rider'),
      );

      smsSpy.mockRestore();
      await api(app)
        .post(`/v1/rides/${ride.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
      await offline(driver).expect(204);
    }, 30_000);
  });

  describe('admin cancel', () => {
    it('cancels a STARTED ride with a mandatory reason, no fee, audited; driver freed', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const ride = await bookAndAccept(rider, driver);
      await driverPost(driver, ride.id, 'arrived', AT_PICKUP).expect(200);
      const otp = (await api(app).get(`/v1/rides/${ride.id}`).set(bearer(rider.token)).expect(200))
        .body.trip_otp;
      await driverPost(driver, ride.id, 'start', { otp, ...AT_PICKUP }).expect(200);

      // Rider and driver cannot cancel a STARTED ride.
      const riderTry = await api(app)
        .post(`/v1/rides/${ride.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(409);
      expect(riderTry.body.error.code).toBe('RIDE_NOT_CANCELLABLE');
      const driverTry = await driverPost(driver, ride.id, 'cancel', { reason: 'x' }).expect(409);
      expect(driverTry.body.error.code).toBe('INVALID_TRANSITION');

      await api(app)
        .post(`/v1/admin/rides/${ride.id}/cancel`)
        .set(bearer(admin))
        .send({})
        .expect(400);
      const res = await api(app)
        .post(`/v1/admin/rides/${ride.id}/cancel`)
        .set(bearer(admin))
        .send({ reason: 'Rider reported an issue' })
        .expect(200);
      expect(res.body).toMatchObject({
        status: 'CANCELLED',
        cancelled_by: 'admin',
        cancellation_fee: 0,
        cancel_reason: 'Rider reported an issue',
      });
      expect(await stateOf(driver)).toBe('idle');
      expect(
        await prisma.auditLog.count({ where: { action: 'ride.cancel', entityId: ride.id } }),
      ).toBe(1);
      await offline(driver).expect(204);
    }, 30_000);
  });
});
