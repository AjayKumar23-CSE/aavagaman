/**
 * Masked calling (D-058): rider and driver call each other through the Aavagaman number.
 * .env.test uses the stub provider (+911140001234, 5 s between calls, callback token).
 */
import { NestExpressApplication } from '@nestjs/platform-express';
import type { Socket } from 'socket.io-client';
import { api, connectSocket, createTestApp, next } from './app';
import { adminLogin, approvedDriver, bearer, CP, INDIA_GATE, loginAs, NEAR_CP, Session } from './fixtures';

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const VIA = '+911140001234';

describe('Phase 5: masked calling (e2e)', () => {
  let app: NestExpressApplication;
  let admin: string;
  const sockets: Socket[] = [];
  const keepalives: NodeJS.Timeout[] = [];

  beforeAll(async () => {
    app = await createTestApp({ worker: true });
    admin = await adminLogin(app);
  });

  afterAll(async () => {
    keepalives.forEach(clearInterval);
    sockets.forEach((s) => s.disconnect());
    await app?.close();
  });

  type Driver = Session & { socket: Socket };

  const onlineDriver = async (name = 'Call Driver'): Promise<Driver> => {
    const d = await approvedDriver(app, admin, name);
    await api(app).post('/v1/driver/online').set(bearer(d.token)).send(NEAR_CP).expect(204);
    const socket = await connectSocket(app, d.token);
    sockets.push(socket);
    keepalives.push(
      setInterval(() => socket.emit('driver:location', { ...NEAR_CP, heading: 0, speed: 0, accuracy: 5 }), 1000),
    );
    return { ...d, socket };
  };

  const bookAndAccept = async (rider: Session, driver: Driver): Promise<Json> => {
    const est = (
      await api(app).post('/v1/fare/estimate').set(bearer(rider.token)).send({ pickup: CP, drop: INDIA_GATE }).expect(200)
    ).body;
    const offer = next<Json>(driver.socket, 'ride:offer', 10_000);
    const ride = (
      await api(app)
        .post('/v1/rides')
        .set(bearer(rider.token))
        .send({ pickup: CP, drop: INDIA_GATE, fare_config_id: est.fare_config_id, payment_method: 'cash' })
        .expect(201)
    ).body;
    expect((await offer).ride_id).toBe(ride.id);
    return (await api(app).post(`/v1/driver/rides/${ride.id}/accept`).set(bearer(driver.token)).expect(200)).body;
  };

  it('numbers stay hidden on both sides; the bridge number is advertised while the trip is live', async () => {
    const rider = await loginAs(app, 'rider');
    const driver = await onlineDriver();
    const accepted = await bookAndAccept(rider, driver);
    expect(accepted.rider.phone).toBeUndefined();
    expect(accepted.rider.call_via).toBe(VIA);
    expect(accepted.rider.phone_masked).toMatch(/^\*+\d{4}$/);

    const riderView = (await api(app).get('/v1/rides/active').set(bearer(rider.token)).expect(200)).body;
    expect(riderView.driver.phone).toBeUndefined();
    expect(riderView.driver.call_via).toBe(VIA);

    // Admins still see the real numbers.
    const adminView = (await api(app).get(`/v1/admin/rides/${accepted.id}`).set(bearer(admin)).expect(200)).body;
    expect(adminView.ride.rider.phone).toMatch(/^\+91\d{10}$/);
    expect(adminView.ride.rider.call_via).toBeUndefined();
    expect(adminView.calls).toEqual([]);
  });

  it('rider and driver can each bridge a call; repeats are throttled; strangers get 404', async () => {
    const rider = await loginAs(app, 'rider');
    const stranger = await loginAs(app, 'rider');
    const driver = await onlineDriver();
    const ride = await bookAndAccept(rider, driver);

    const byRider = (await api(app).post(`/v1/rides/${ride.id}/call`).set(bearer(rider.token)).expect(200)).body;
    expect(byRider).toMatchObject({ ride_id: ride.id, caller_id: rider.id, callee_id: driver.id, provider: 'stub', status: 'initiated', via: VIA });
    expect(byRider.id).toMatch(/^[0-9a-f-]{36}$/);

    const again = await api(app).post(`/v1/rides/${ride.id}/call`).set(bearer(rider.token)).expect(429);
    expect(again.body.error.code).toBe('CALL_TOO_SOON');

    const byDriver = (await api(app).post(`/v1/driver/rides/${ride.id}/call`).set(bearer(driver.token)).expect(200)).body;
    expect(byDriver).toMatchObject({ caller_id: driver.id, callee_id: rider.id, status: 'initiated', via: VIA });

    await api(app).post(`/v1/rides/${ride.id}/call`).set(bearer(stranger.token)).expect(404);

    const detail = (await api(app).get(`/v1/admin/rides/${ride.id}`).set(bearer(admin)).expect(200)).body;
    expect(detail.calls.map((c: Json) => c.caller_id)).toEqual([rider.id, driver.id]);
  });

  it('the provider callback records the outcome and talk time; the token is required', async () => {
    const rider = await loginAs(app, 'rider');
    const driver = await onlineDriver();
    const ride = await bookAndAccept(rider, driver);
    const call = (await api(app).post(`/v1/rides/${ride.id}/call`).set(bearer(rider.token)).expect(200)).body;
    const sid = (await api(app).get(`/v1/admin/rides/${ride.id}`).set(bearer(admin)).expect(200)).body.calls[0]
      .provider_call_id as string | undefined;

    await api(app)
      .post('/v1/webhooks/calls/exotel')
      .type('form')
      .send({ CallSid: 'whatever', Status: 'completed' })
      .expect(401);

    // Form-encoded, as Exotel sends it.
    const unknown = await api(app)
      .post('/v1/webhooks/calls/exotel?token=call-hook-secret')
      .type('form')
      .send({ CallSid: 'not-ours', Status: 'completed', ConversationDuration: '12' })
      .expect(200);
    expect(unknown.body.result).toBe('unknown');

    const providerCallId = sid ?? call.provider_call_id;
    // JSON, which is what the provider asks Exotel for (StatusCallbackContentType).
    const ok = await api(app)
      .post('/v1/webhooks/calls/exotel?token=call-hook-secret')
      .send({ CallSid: providerCallId, Status: 'completed', ConversationDuration: 42 })
      .expect(200);
    expect(ok.body.result).toBe('recorded');

    const detail = (await api(app).get(`/v1/admin/rides/${ride.id}`).set(bearer(admin)).expect(200)).body;
    expect(detail.calls[0]).toMatchObject({ status: 'completed', duration_s: 42 });
    expect(detail.calls[0].ended_at).toBeTruthy();
  });

  it('no call before a driver is assigned or after the ride ends', async () => {
    const rider = await loginAs(app, 'rider');
    const driver = await onlineDriver();
    const ride = await bookAndAccept(rider, driver);
    await api(app).post(`/v1/rides/${ride.id}/cancel`).set(bearer(rider.token)).send({}).expect(200);
    const res = await api(app).post(`/v1/rides/${ride.id}/call`).set(bearer(rider.token)).expect(409);
    expect(res.body.error.code).toBe('RIDE_NOT_CALLABLE');
  });
});
