/**
 * SPEC §20 Phase 4 acceptance, API level (fake Razorpay on :5056; cash fallback 2 s,
 * poll every 1 s in .env.test): online payment marks the ride PAID via verify and via
 * webhook (idempotent); the poller catches a missed capture; settlement maths match a hand
 * calculation; admin reassign updates both drivers; a fare config change applies to the
 * next estimate; CSV export has the expected header.
 */
import { createHmac } from 'node:crypto';
import { NestExpressApplication } from '@nestjs/platform-express';
import type { Socket } from 'socket.io-client';
import { PrismaService } from '../../src/common/prisma.service';
import { RedisService } from '../../src/common/redis.service';
import { settlementTotals } from '../../src/modules/settlements/settlement.math';
import { api, connectSocket, createTestApp, next, sleep } from './app';
import { FAKE_RAZORPAY_PORT } from './fake-razorpay';
import {
  adminLogin,
  approvedDriver,
  bearer,
  CP,
  FARTHER_CP,
  INDIA_GATE,
  loginAs,
  MEERUT,
  NEAR_CP,
  Session,
} from './fixtures';

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const AT_PICKUP = { lat: CP.lat, lng: CP.lng + 0.00036 };
const KEY_SECRET = 'rzp_test_secret';
const WEBHOOK_SECRET = 'whsec_test';
const sign = (secret: string, data: string) =>
  createHmac('sha256', secret).update(data).digest('hex');

describe('Phase 4: payments, settlements, admin (e2e)', () => {
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

  afterEach(() => keepalives.splice(0).forEach(clearInterval));

  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    await app?.close();
  });

  type Driver = Session & { socket: Socket };

  const socketFor = async (s: Session | string) => {
    const sock = await connectSocket(app, typeof s === 'string' ? s : s.token);
    sockets.push(sock);
    return sock;
  };

  const onlineDriver = async (pos = NEAR_CP, name = 'Pay Driver'): Promise<Driver> => {
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
  const driverPost = (d: Session, rideId: string, action: string, body: object = {}) =>
    api(app).post(`/v1/driver/rides/${rideId}/${action}`).set(bearer(d.token)).send(body);

  const bookAndAccept = async (
    rider: Session,
    driver: Driver,
    payment: 'cash' | 'online' = 'cash',
  ): Promise<Json> => {
    const est = (
      await api(app)
        .post('/v1/fare/estimate')
        .set(bearer(rider.token))
        .send({ pickup: CP, drop: INDIA_GATE })
        .expect(200)
    ).body;
    const offer = next<Json>(driver.socket, 'ride:offer', 10_000);
    const ride = (
      await api(app)
        .post('/v1/rides')
        .set(bearer(rider.token))
        .send({
          pickup: CP,
          drop: INDIA_GATE,
          fare_config_id: est.fare_config_id,
          payment_method: payment,
        })
        .expect(201)
    ).body;
    expect((await offer).ride_id).toBe(ride.id);
    return (await driverPost(driver, ride.id, 'accept').expect(200)).body;
  };

  /** Runs a ride through to COMPLETED; returns the driver view. */
  const completeRide = async (
    rider: Session,
    driver: Driver,
    payment: 'cash' | 'online' = 'cash',
  ): Promise<Json> => {
    const ride = await bookAndAccept(rider, driver, payment);
    await driverPost(driver, ride.id, 'arrived', AT_PICKUP).expect(200);
    const otp = (await api(app).get(`/v1/rides/${ride.id}`).set(bearer(rider.token)).expect(200))
      .body.trip_otp;
    await driverPost(driver, ride.id, 'start', { otp, ...AT_PICKUP }).expect(200);
    return (
      await driverPost(driver, ride.id, 'complete', {
        lat: INDIA_GATE.lat,
        lng: INDIA_GATE.lng,
      }).expect(200)
    ).body;
  };

  const createOrder = (rider: Session, rideId: string) =>
    api(app).post(`/v1/rides/${rideId}/payment/order`).set(bearer(rider.token));

  const webhook = (event: string, entity: object, secret = WEBHOOK_SECRET) => {
    const body = JSON.stringify({ entity: 'event', event, payload: { payment: { entity } } });
    return api(app)
      .post('/v1/webhooks/razorpay')
      .set('Content-Type', 'application/json')
      .set('X-Razorpay-Signature', sign(secret, body))
      .send(body);
  };

  describe('online payments (SPEC §15)', () => {
    it('order → checkout verify marks the ride PAID; bad signatures and double orders are refused', async () => {
      const rider = await loginAs(app, 'rider');
      const riderSocket = await socketFor(rider);
      const driver = await onlineDriver();
      const done = await completeRide(rider, driver, 'online');
      expect(done.payment_method).toBe('online');

      const order = (await createOrder(rider, done.id).expect(200)).body;
      expect(order).toMatchObject({
        amount: done.amount_due * 100,
        currency: 'INR',
        key_id: 'rzp_test_key',
      });
      expect(order.razorpay_order_id).toMatch(/^order_/);
      // Idempotent while pending.
      expect((await createOrder(rider, done.id).expect(200)).body.razorpay_order_id).toBe(
        order.razorpay_order_id,
      );

      const bad = await api(app)
        .post(`/v1/rides/${done.id}/payment/verify`)
        .set(bearer(rider.token))
        .send({
          razorpay_order_id: order.razorpay_order_id,
          razorpay_payment_id: 'pay_x',
          razorpay_signature: 'a'.repeat(64),
        })
        .expect(400);
      expect(bad.body.error.code).toBe('SIGNATURE_INVALID');

      const paidEvent = next<Json>(riderSocket, 'payment:status', 5000);
      const driverPaid = next<Json>(driver.socket, 'payment:status', 5000);
      const sig = sign(KEY_SECRET, `${order.razorpay_order_id}|pay_ok1`);
      const verified = await api(app)
        .post(`/v1/rides/${done.id}/payment/verify`)
        .set(bearer(rider.token))
        .send({
          razorpay_order_id: order.razorpay_order_id,
          razorpay_payment_id: 'pay_ok1',
          razorpay_signature: sig,
        })
        .expect(200);
      expect(verified.body).toMatchObject({
        status: 'paid',
        gateway_payment_id: 'pay_ok1',
        amount: done.amount_due,
      });
      expect(await paidEvent).toMatchObject({ ride_id: done.id, status: 'paid' });
      expect(await driverPaid).toMatchObject({ ride_id: done.id, status: 'paid' });
      expect((await prisma.ride.findUniqueOrThrow({ where: { id: done.id } })).status).toBe('PAID');
      expect(await redis.get(`driver:${driver.id}:state`)).toBe('idle');
      await createOrder(rider, done.id).expect(409);
      await driverPost(driver, done.id, 'cash-collected').expect(409);
      await offline(driver).expect(204);
    }, 40_000);

    it('webhook payment.captured is the source of truth, idempotent, and signature-checked', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const done = await completeRide(rider, driver, 'online');
      const order = (await createOrder(rider, done.id).expect(200)).body;
      const entity = {
        id: 'pay_wh1',
        order_id: order.razorpay_order_id,
        status: 'captured',
        method: 'upi',
        amount: order.amount,
      };

      await webhook('payment.captured', entity, 'wrong-secret').expect(400);
      expect((await webhook('payment.captured', entity).expect(200)).body.result).toBe('captured');
      expect((await prisma.ride.findUniqueOrThrow({ where: { id: done.id } })).status).toBe('PAID');
      expect(await prisma.payment.findUniqueOrThrow({ where: { rideId: done.id } })).toMatchObject({
        status: 'paid',
        method: 'upi',
        gatewayPaymentId: 'pay_wh1',
      });

      // Duplicate delivery changes nothing.
      expect((await webhook('payment.captured', entity).expect(200)).body.result).toBe('captured');
      expect(await prisma.rideEvent.count({ where: { rideId: done.id, toStatus: 'PAID' } })).toBe(
        1,
      );
      expect(
        (
          await webhook('payment.captured', {
            ...entity,
            id: 'pay_other',
            order_id: 'order_unknown',
          }).expect(200)
        ).body.result,
      ).toBe('unknown-order');
      await offline(driver).expect(204);
    }, 40_000);

    it('payment.failed marks the attempt failed and tells the rider; cash can then be collected', async () => {
      const rider = await loginAs(app, 'rider');
      const riderSocket = await socketFor(rider);
      const driver = await onlineDriver();
      const done = await completeRide(rider, driver, 'online');
      const order = (await createOrder(rider, done.id).expect(200)).body;
      const failed = next<Json>(riderSocket, 'payment:status', 5000, (p) => p.status === 'failed');
      await webhook('payment.failed', {
        id: 'pay_f1',
        order_id: order.razorpay_order_id,
        status: 'failed',
        method: 'card',
        amount: order.amount,
      }).expect(200);
      expect(await failed).toMatchObject({ ride_id: done.id, status: 'failed', method: 'card' });
      expect((await prisma.payment.findUniqueOrThrow({ where: { rideId: done.id } })).status).toBe(
        'failed',
      );
      const paid = await driverPost(driver, done.id, 'cash-collected').expect(200);
      expect(paid.body.status).toBe('PAID');
      expect((await prisma.payment.findUniqueOrThrow({ where: { rideId: done.id } })).method).toBe(
        'cash',
      );
      await offline(driver).expect(204);
    }, 40_000);

    it('a fresh pending online attempt blocks cash for PAYMENT_CASH_FALLBACK_SECONDS', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const done = await completeRide(rider, driver, 'online');
      await createOrder(rider, done.id).expect(200);
      const blocked = await driverPost(driver, done.id, 'cash-collected').expect(409);
      expect(blocked.body.error.code).toBe('PAYMENT_PENDING');
      await sleep(2300);
      await driverPost(driver, done.id, 'cash-collected').expect(200);
      await offline(driver).expect(204);
    }, 40_000);

    it('the poller catches a capture the webhook missed', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const done = await completeRide(rider, driver, 'online');
      const order = (await createOrder(rider, done.id).expect(200)).body;
      const res = await fetch(`http://localhost:${FAKE_RAZORPAY_PORT}/__test/capture`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          order_id: order.razorpay_order_id,
          payment_id: 'pay_poll1',
          method: 'wallet',
        }),
      });
      expect(res.ok).toBe(true);
      // Pending attempts become eligible after 2 s; the poll runs every 1 s.
      let status = 'COMPLETED';
      for (let i = 0; i < 12 && status !== 'PAID'; i++) {
        await sleep(500);
        status = (await prisma.ride.findUniqueOrThrow({ where: { id: done.id } })).status;
      }
      expect(status).toBe('PAID');
      expect(await prisma.payment.findUniqueOrThrow({ where: { rideId: done.id } })).toMatchObject({
        status: 'paid',
        method: 'wallet',
        gatewayPaymentId: 'pay_poll1',
      });
      await offline(driver).expect(204);
    }, 40_000);
  });

  describe('earnings and settlements (SPEC §7.3, §15)', () => {
    it('earnings today/week and a weekly settlement that matches a hand calculation', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver(NEAR_CP, 'Settle Driver');
      const cash = await completeRide(rider, driver, 'cash');
      await driverPost(driver, cash.id, 'cash-collected').expect(200);
      const online = await completeRide(rider, driver, 'online');
      const order = (await createOrder(rider, online.id).expect(200)).body;
      await webhook('payment.captured', {
        id: 'pay_s1',
        order_id: order.razorpay_order_id,
        status: 'captured',
        method: 'upi',
        amount: order.amount,
      }).expect(200);

      const today = (
        await api(app).get('/v1/driver/earnings?period=today').set(bearer(driver.token)).expect(200)
      ).body;
      expect(today.rides).toBe(2);
      expect(today.gross).toBe(cash.final_fare + online.final_fare);
      expect(today.cash_collected).toBe(cash.amount_due);
      expect(today.online).toBe(online.amount_due);
      expect(today.net).toBeCloseTo(today.gross - today.commission - today.gst, 2);
      const week = (
        await api(app).get('/v1/driver/earnings?period=week').set(bearer(driver.token)).expect(200)
      ).body;
      expect(week.rides).toBeGreaterThanOrEqual(2);

      // Settlements need a finished week: move these rides' payments back 7 days.
      const lastWeek = new Date(Date.now() - 7 * 86_400_000);
      await prisma.ride.updateMany({
        where: { id: { in: [cash.id, online.id] } },
        data: { paidAt: lastWeek },
      });
      const generated = (
        await api(app)
          .post('/v1/admin/settlements/generate')
          .set(bearer(admin))
          .send({})
          .expect(200)
      ).body;
      const mine = generated.settlements.find((s: Json) => s.driver_id === driver.id);
      const expected = settlementTotals([
        {
          finalFare: cash.final_fare,
          gstPct: 5,
          commissionPct: 15,
          paidWith: 'cash',
          amountPaid: cash.amount_due,
        },
        {
          finalFare: online.final_fare,
          gstPct: 5,
          commissionPct: 15,
          paidWith: 'online',
          amountPaid: online.amount_due,
        },
      ]);
      expect(mine).toMatchObject({
        rides_count: 2,
        gross_fares: expected.gross_fares,
        commission: expected.commission,
        cash_collected: expected.cash_collected,
        online_collected: expected.online_collected,
        amount_payable: expected.amount_payable,
        settled_at: null,
      });
      // amount_payable = online − commission − gst_on_gross
      expect(mine.amount_payable).toBeCloseTo(
        mine.online_collected - mine.commission - expected.gst_on_gross,
        2,
      );

      const thisWeek = await api(app)
        .post('/v1/admin/settlements/generate')
        .set(bearer(admin))
        .send({ week: new Date().toISOString().slice(0, 10) })
        .expect(422);
      expect(thisWeek.body.error.code).toBe('WEEK_NOT_OVER');

      const settled = (
        await api(app)
          .post(`/v1/admin/settlements/${mine.id}/settle`)
          .set(bearer(admin))
          .send({ reference: 'NEFT UTR 42' })
          .expect(200)
      ).body;
      expect(settled).toMatchObject({ reference: 'NEFT UTR 42', settled_by: expect.any(String) });
      await api(app)
        .post(`/v1/admin/settlements/${mine.id}/settle`)
        .set(bearer(admin))
        .send({ reference: 'again' })
        .expect(409);
      const list = (
        await api(app)
          .get(`/v1/admin/settlements?week=${lastWeek.toISOString().slice(0, 10)}`)
          .set(bearer(admin))
          .expect(200)
      ).body;
      expect(list.find((s: Json) => s.id === mine.id)).toMatchObject({
        driver_name: 'Settle Driver',
        reference: 'NEFT UTR 42',
      });
      await offline(driver).expect(204);
    }, 60_000);
  });

  describe('admin rides', () => {
    it('list/detail, reassign (both drivers updated), adjust-fare (logged) and mark-cash', async () => {
      const rider = await loginAs(app, 'rider');
      const riderSocket = await socketFor(rider);
      const a = await onlineDriver(NEAR_CP, 'Driver A');
      const b = await onlineDriver(FARTHER_CP, 'Driver B');
      const ride = await bookAndAccept(rider, a);

      const list = (
        await api(app)
          .get(`/v1/admin/rides?status=ACCEPTED&driver_id=${a.id}`)
          .set(bearer(admin))
          .expect(200)
      ).body;
      expect(list.data.map((r: Json) => r.id)).toContain(ride.id);
      expect(list.data[0].rider.phone).toMatch(/^\+91/); // admins see full numbers

      // Reassign A → B: A told it lost the ride, B gets ACCEPTED, rider sees the new driver.
      const lost = next<Json>(a.socket, 'ride:status', 5000, (p) => p.reassigned === true);
      const bGot = next<Json>(b.socket, 'ride:status', 5000, (p) => p.status === 'ACCEPTED');
      const riderSees = next<Json>(riderSocket, 'ride:status', 5000, (p) => p.driver?.id === b.id);
      const busy = await api(app)
        .post(`/v1/admin/rides/${ride.id}/reassign`)
        .set(bearer(admin))
        .send({ driver_id: a.id })
        .expect(409);
      expect(busy.body.error.code).toBe('DRIVER_NOT_IDLE'); // A is on this very ride
      const re = await api(app)
        .post(`/v1/admin/rides/${ride.id}/reassign`)
        .set(bearer(admin))
        .send({ driver_id: b.id })
        .expect(200);
      expect(re.body.driver.id).toBe(b.id);
      await Promise.all([lost, bGot, riderSees]);
      expect(await redis.get(`driver:${a.id}:state`)).toBe('idle');
      expect(await redis.get(`driver:${b.id}:state`)).toBe('on_trip');
      await driverPost(a, ride.id, 'arrived', AT_PICKUP).expect(404);

      await driverPost(b, ride.id, 'arrived', AT_PICKUP).expect(200);
      const otp = (await api(app).get(`/v1/rides/${ride.id}`).set(bearer(rider.token)).expect(200))
        .body.trip_otp;
      await driverPost(b, ride.id, 'start', { otp, ...AT_PICKUP }).expect(200);
      const done = (
        await driverPost(b, ride.id, 'complete', {
          lat: INDIA_GATE.lat,
          lng: INDIA_GATE.lng,
        }).expect(200)
      ).body;

      const adjusted = await api(app)
        .post(`/v1/admin/rides/${ride.id}/adjust-fare`)
        .set(bearer(admin))
        .send({ final_fare: done.final_fare + 20, reason: 'Toll added' })
        .expect(200);
      expect(adjusted.body.final_fare).toBe(done.final_fare + 20);
      const marked = await api(app)
        .post(`/v1/admin/rides/${ride.id}/mark-cash`)
        .set(bearer(admin))
        .expect(200);
      expect(marked.body.status).toBe('PAID');
      expect(
        Number((await prisma.payment.findUniqueOrThrow({ where: { rideId: ride.id } })).amount),
      ).toBe(done.final_fare + 20);

      const detail = (
        await api(app).get(`/v1/admin/rides/${ride.id}`).set(bearer(admin)).expect(200)
      ).body;
      expect(detail.ride).toMatchObject({ id: ride.id, status: 'PAID', trip_otp: otp });
      // B was asked in the first round too (D-055) and lost to A before the admin moved the ride.
      expect(
        detail.offers
          .map((o: Json) => [o.driver_id, o.response])
          .sort((x: string[], y: string[]) => x.join().localeCompare(y.join())),
      ).toEqual(
        [
          [a.id, 'accepted'],
          [b.id, 'withdrawn'],
          [b.id, 'accepted'],
        ].sort((x, y) => x.join().localeCompare(y.join())),
      );
      expect(detail.events.map((e: Json) => e.to_status)).toEqual([
        'REQUESTED',
        'ACCEPTED',
        'ACCEPTED',
        'ARRIVED',
        'STARTED',
        'COMPLETED',
        'COMPLETED',
        'PAID',
      ]);
      expect(detail.payment).toMatchObject({ method: 'cash', status: 'paid' });
      expect(detail.track.geometry.type).toBe('LineString');
      expect(detail.track.geometry.coordinates.length).toBeGreaterThan(0);
      const audit = (
        await api(app)
          .get(`/v1/admin/audit?entity=ride&entity_id=${ride.id}`)
          .set(bearer(admin))
          .expect(200)
      ).body;
      expect(audit.data.map((a: Json) => a.action).sort()).toEqual([
        'ride.adjust_fare',
        'ride.mark_cash',
        'ride.reassign',
      ]);
      expect(audit.data[0].actor_name).toBe('Admin');
      await offline(a).expect(204);
      await offline(b).expect(204);
    }, 60_000);
  });

  describe('dashboard, live map, riders, config, reports, sos', () => {
    it('dashboard counts and the live snapshot + admin:live stream', async () => {
      const driver = await onlineDriver(NEAR_CP, 'Live Driver');
      const rider = await loginAs(app, 'rider');
      const ride = await bookAndAccept(rider, driver);

      const dash = (await api(app).get('/v1/admin/dashboard').set(bearer(admin)).expect(200)).body;
      expect(dash.rides_total).toBeGreaterThanOrEqual(1);
      expect(dash.online_drivers).toBeGreaterThanOrEqual(1);
      expect(dash).toEqual(
        expect.objectContaining({
          revenue: expect.any(Number),
          cancellations: expect.any(Number),
          pending_drivers: expect.any(Number),
          open_sos: expect.any(Number),
        }),
      );

      const live = (await api(app).get('/v1/admin/live').set(bearer(admin)).expect(200)).body;
      expect(live.drivers.find((d: Json) => d.driver_id === driver.id)).toMatchObject({
        state: 'on_trip',
        name: 'Live Driver',
        lat: NEAR_CP.lat,
      });
      expect(live.rides.find((r: Json) => r.ride_id === ride.id)).toMatchObject({
        status: 'ACCEPTED',
        driver_id: driver.id,
      });

      const adminSocket = await socketFor(admin);
      const stream = await next<Json>(adminSocket, 'admin:live', 6000);
      expect(stream.rides.some((r: Json) => r.ride_id === ride.id)).toBe(true);
      adminSocket.disconnect();
      await api(app)
        .post(`/v1/rides/${ride.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
      await offline(driver).expect(204);
    }, 30_000);

    it('riders: list, block (session revoked, login refused), unblock', async () => {
      const phone = '+919' + String(Math.floor(Math.random() * 1e9)).padStart(9, '0');
      const rider = await loginAs(app, 'rider', phone);
      await api(app)
        .patch('/v1/me')
        .set(bearer(rider.token))
        .send({ name: 'Blocky McRide' })
        .expect(200);
      const list = (await api(app).get('/v1/admin/riders?q=Blocky').set(bearer(admin)).expect(200))
        .body;
      expect(list.data[0]).toMatchObject({ id: rider.id, status: 'active', rides_count: 0 });

      await api(app)
        .post(`/v1/admin/riders/${rider.id}/block`)
        .set(bearer(admin))
        .send({})
        .expect(400);
      const blocked = await api(app)
        .post(`/v1/admin/riders/${rider.id}/block`)
        .set(bearer(admin))
        .send({ reason: 'Abuse' })
        .expect(200);
      expect(blocked.body.status).toBe('blocked');
      await api(app)
        .post('/v1/auth/otp/send')
        .set('X-Forwarded-For', '10.200.0.1')
        .send({ phone, role: 'rider' })
        .expect(200);
      const login = await api(app)
        .post('/v1/auth/otp/verify')
        .send({ phone, role: 'rider', code: '123456' })
        .expect(403);
      expect(login.body.error.code).toBe('USER_BLOCKED');
      const unblocked = await api(app)
        .post(`/v1/admin/riders/${rider.id}/unblock`)
        .set(bearer(admin))
        .send({})
        .expect(200);
      expect(unblocked.body.status).toBe('active');
    });

    it('fare config: preview matches Appendix B and a new config applies to the next estimate', async () => {
      const preview = (
        await api(app)
          .post('/v1/admin/fare-config/preview')
          .set(bearer(admin))
          .send({
            base_fare: 50,
            per_km: 12,
            per_min: 1.5,
            min_fare: 80,
            distance_m: 10_000,
            duration_s: 1800,
            at: '2026-09-28T06:30:00Z',
          })
          .expect(200)
      ).body;
      expect(preview).toEqual({ fare: 215, fare_min: 204, fare_max: 237, cap: 269 });

      const before = (await api(app).get('/v1/admin/fare-config').set(bearer(admin)).expect(200))
        .body;
      const rider = await loginAs(app, 'rider');
      const est1 = (
        await api(app)
          .post('/v1/fare/estimate')
          .set(bearer(rider.token))
          .send({ pickup: CP, drop: INDIA_GATE })
          .expect(200)
      ).body;
      expect(est1.fare_config_id).toBe(before.current_id);

      const created = (
        await api(app)
          .post('/v1/admin/fare-config')
          .set(bearer(admin))
          .send({ base_fare: 500, per_km: 12, per_min: 1.5, min_fare: 80 })
          .expect(201)
      ).body;
      const est2 = (
        await api(app)
          .post('/v1/fare/estimate')
          .set(bearer(rider.token))
          .send({ pickup: CP, drop: INDIA_GATE })
          .expect(200)
      ).body;
      expect(est2.fare_config_id).toBe(created.id);
      expect(est2.fare_min).toBeGreaterThan(est1.fare_min + 400);
      // Restore the seed tariff for the other tests (a newer effective_from wins).
      await api(app)
        .post('/v1/admin/fare-config')
        .set(bearer(admin))
        .send({
          base_fare: 50,
          per_km: 12,
          per_min: 1.5,
          min_fare: 80,
          cancellation_fee: 30,
          commission_pct: 15,
        })
        .expect(201);
      const audit = (
        await api(app).get('/v1/admin/audit?entity=fare_config').set(bearer(admin)).expect(200)
      ).body;
      expect(audit.total).toBeGreaterThanOrEqual(2);
    });

    it('service areas: list GeoJSON, add a polygon that puts Meerut in service, deactivate it, reject bad input', async () => {
      const list = (await api(app).get('/v1/admin/service-areas').set(bearer(admin)).expect(200))
        .body;
      expect(list.type).toBe('FeatureCollection');
      expect(list.features.map((f: Json) => f.properties.name)).toContain('Delhi NCR');

      const rider = await loginAs(app, 'rider');
      const estBefore = (
        await api(app)
          .post('/v1/fare/estimate')
          .set(bearer(rider.token))
          .send({ pickup: MEERUT, drop: CP })
          .expect(200)
      ).body;
      expect(estBefore.in_service_area.pickup).toBe(false);

      const square = {
        type: 'Polygon',
        coordinates: [
          [
            [77.6, 28.9],
            [77.8, 28.9],
            [77.8, 29.05],
            [77.6, 29.05],
            [77.6, 28.9],
          ],
        ],
      };
      const bad = await api(app)
        .post('/v1/admin/service-areas')
        .set(bearer(admin))
        .send({
          name: 'Bad',
          polygon: {
            type: 'Polygon',
            coordinates: [
              [
                [0, 0],
                [1, 1],
                [0, 0],
              ],
            ],
          },
        })
        .expect(422);
      expect(bad.body.error.code).toBe('INVALID_POLYGON');
      const area = (
        await api(app)
          .post('/v1/admin/service-areas')
          .set(bearer(admin))
          .send({ name: 'Meerut pilot', polygon: square })
          .expect(201)
      ).body;
      expect(area.geometry.type).toBe('Polygon');
      const estAfter = (
        await api(app)
          .post('/v1/fare/estimate')
          .set(bearer(rider.token))
          .send({ pickup: MEERUT, drop: CP })
          .expect(200)
      ).body;
      expect(estAfter.in_service_area.pickup).toBe(true);

      const off = (
        await api(app)
          .patch(`/v1/admin/service-areas/${area.id}`)
          .set(bearer(admin))
          .send({ active: false, name: 'Meerut (paused)' })
          .expect(200)
      ).body;
      expect(off.properties).toMatchObject({ active: false, name: 'Meerut (paused)' });
      const estOff = (
        await api(app)
          .post('/v1/fare/estimate')
          .set(bearer(rider.token))
          .send({ pickup: MEERUT, drop: CP })
          .expect(200)
      ).body;
      expect(estOff.in_service_area.pickup).toBe(false);
    });

    it('daily report in JSON and CSV', async () => {
      const today = new Date(Date.now() + 5.5 * 3_600_000).toISOString().slice(0, 10);
      const json = (
        await api(app)
          .get(`/v1/admin/reports/daily?from=${today}&to=${today}`)
          .set(bearer(admin))
          .expect(200)
      ).body;
      expect(json.data).toHaveLength(1);
      expect(json.data[0]).toMatchObject({ day: today });
      expect(json.data[0].requested).toBeGreaterThanOrEqual(1);
      expect(json.data[0].paid_rides).toBeGreaterThanOrEqual(1);
      expect(json.data[0].revenue).toBeGreaterThan(0);
      expect(json.data[0].revenue).toBeCloseTo(json.data[0].cash + json.data[0].online, 2);

      const csv = await api(app)
        .get(`/v1/admin/reports/daily?from=${today}&to=${today}&format=csv`)
        .set(bearer(admin))
        .expect(200);
      expect(csv.headers['content-type']).toMatch(/text\/csv/);
      expect(csv.headers['content-disposition']).toContain('.csv');
      expect(csv.text.split('\r\n')[0]).toBe(
        'day,requested,completed,cancelled,no_driver,paid_rides,revenue,gross_fares,gst,commission,cash,online',
      );
      await api(app)
        .get('/v1/admin/reports/daily?from=2026-02-01&to=2026-01-01')
        .set(bearer(admin))
        .expect(400);
    });

    it('sos list and acknowledge', async () => {
      const rider = await loginAs(app, 'rider');
      const driver = await onlineDriver();
      const ride = await bookAndAccept(rider, driver);
      const sos = (
        await api(app)
          .post(`/v1/rides/${ride.id}/sos`)
          .set(bearer(rider.token))
          .send({ lat: CP.lat, lng: CP.lng })
          .expect(201)
      ).body;
      const open = (
        await api(app).get('/v1/admin/sos?acknowledged=false').set(bearer(admin)).expect(200)
      ).body;
      expect(open.data.find((s: Json) => s.id === sos.id)).toMatchObject({
        ride_id: ride.id,
        user_role: 'rider',
        lat: CP.lat,
        lng: CP.lng,
        acknowledged_at: null,
      });
      const ack = (
        await api(app).post(`/v1/admin/sos/${sos.id}/ack`).set(bearer(admin)).expect(200)
      ).body;
      expect(ack.acknowledged_by).toBeDefined();
      await api(app).post(`/v1/admin/sos/${sos.id}/ack`).set(bearer(admin)).expect(409);
      const closed = (
        await api(app).get('/v1/admin/sos?acknowledged=true').set(bearer(admin)).expect(200)
      ).body;
      expect(closed.data.some((s: Json) => s.id === sos.id)).toBe(true);
      await api(app)
        .post(`/v1/rides/${ride.id}/cancel`)
        .set(bearer(rider.token))
        .send({})
        .expect(200);
      await offline(driver).expect(204);
    }, 30_000);
  });
});

describe('Phase 4: admin settings (e2e)', () => {
  let app: NestExpressApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });

  afterAll(async () => {
    await app?.close();
  });

  it('changes the admin password, signs out other sessions, and keeps the login lockout', async () => {
    const admin = await adminLogin(app);
    const other = (
      await api(app)
        .post('/v1/auth/admin/login')
        .send({ email: 'admin@test.local', password: 'admin12345' })
        .expect(200)
    ).body;

    await api(app)
      .post('/v1/admin/settings/password')
      .set(bearer(admin))
      .send({ current_password: 'admin12345', new_password: 'short1' })
      .expect(400);
    const wrong = await api(app)
      .post('/v1/admin/settings/password')
      .set(bearer(admin))
      .send({ current_password: 'nope-nope', new_password: 'Str0ngerPassw0rd' })
      .expect(401);
    expect(wrong.body.error.code).toBe('INVALID_CREDENTIALS');
    const same = await api(app)
      .post('/v1/admin/settings/password')
      .set(bearer(admin))
      .send({ current_password: 'admin12345', new_password: 'admin12345' })
      .expect(422);
    expect(same.body.error.code).toBe('PASSWORD_REUSED');

    const changed = (
      await api(app)
        .post('/v1/admin/settings/password')
        .set(bearer(admin))
        .send({ current_password: 'admin12345', new_password: 'Str0ngerPassw0rd' })
        .expect(200)
    ).body;
    expect(changed.access_token).toBeDefined();
    // The other browser's refresh token is revoked; the old password no longer works; the new one does.
    await api(app)
      .post('/v1/auth/refresh')
      .send({ refresh_token: other.refresh_token })
      .expect(401);
    await api(app)
      .post('/v1/auth/refresh')
      .send({ refresh_token: changed.refresh_token })
      .expect(200);
    await api(app)
      .post('/v1/auth/admin/login')
      .send({ email: 'admin@test.local', password: 'admin12345' })
      .expect(401);
    const fresh = (
      await api(app)
        .post('/v1/auth/admin/login')
        .send({ email: 'admin@test.local', password: 'Str0ngerPassw0rd' })
        .expect(200)
    ).body;
    // Restore the seed password for the other suites.
    await api(app)
      .post('/v1/admin/settings/password')
      .set(bearer(fresh.access_token))
      .send({ current_password: 'Str0ngerPassw0rd', new_password: 'admin12345' })
      .expect(200);
    const audit = (
      await api(app).get('/v1/admin/audit?entity=user').set(bearer(fresh.access_token)).expect(200)
    ).body;
    expect(audit.data.some((a: Json) => a.action === 'admin.password_change')).toBe(true);
  });
});
