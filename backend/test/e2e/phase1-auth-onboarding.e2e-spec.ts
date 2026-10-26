/**
 * SPEC §20 Phase 1 acceptance, API level:
 * rider OTP login; driver registers, uploads 6 documents, sees pending; admin
 * approves and the driver becomes approved; a rejected document carries the
 * note; the 6th OTP in an hour is rejected. Plus JWT rotation and role guards.
 */
import { NestExpressApplication } from '@nestjs/platform-express';
import { PrismaService } from '../../src/common/prisma.service';
import { api, createTestApp, randomIp, randomPhone } from './app';

const BYPASS = '123456';
const ADMIN = { email: 'admin@test.local', password: 'admin12345' };
const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

describe('Phase 1: auth and driver onboarding (e2e)', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createTestApp();
    prisma = app.get(PrismaService);
  });

  afterAll(async () => {
    await app?.close();
  });

  // Each send from its own client IP so the per-IP limit (3/min) is not what a test hits.
  const otpSend = (body: object) =>
    api(app).post('/v1/auth/otp/send').set('X-Forwarded-For', randomIp()).send(body);

  const login = async (phone: string, role: 'rider' | 'driver') => {
    await otpSend({ phone, role }).expect(200);
    const res = await api(app)
      .post('/v1/auth/otp/verify')
      .send({
        phone,
        role,
        code: BYPASS,
        device: { platform: 'android', fcm_token: 'fcm-token-123', app_version: '0.1.0' },
      })
      .expect(200);
    return res.body as {
      access_token: string;
      refresh_token: string;
      user: { id: string; phone: string; name: string | null; role: string };
    };
  };

  const adminToken = async () => {
    const res = await api(app).post('/v1/auth/admin/login').send(ADMIN).expect(200);
    return res.body.access_token as string;
  };

  describe('rider', () => {
    it('logs in with OTP, sets a name, registers an FCM token', async () => {
      const phone = randomPhone();
      const sent = await otpSend({ phone, role: 'rider' }).expect(200);
      expect(sent.body).toEqual({ sent: true, ttl: 300 });

      const { access_token, user } = await login(phone, 'rider');
      expect(user).toMatchObject({ phone, role: 'rider', name: null, status: 'active' });

      const me = await api(app)
        .patch('/v1/me')
        .set(bearer(access_token))
        .send({ name: 'Asha Verma' })
        .expect(200);
      expect(me.body.name).toBe('Asha Verma');
      await api(app)
        .post('/v1/me/fcm-token')
        .set(bearer(access_token))
        .send({ token: 'fcm-token-456' })
        .expect(204);
      await api(app).get('/v1/me').set(bearer(access_token)).expect(200);
    });

    it('accepts local phone formats and rejects invalid numbers', async () => {
      const local = randomPhone().slice(3);
      const { user } = await login(local, 'rider');
      expect(user.phone).toBe('+91' + local);
      const bad = await otpSend({ phone: '12345', role: 'rider' }).expect(400);
      expect(bad.body.error.code).toBe('INVALID_PHONE');
    });

    it('rejects a wrong code with a generic error', async () => {
      const phone = randomPhone();
      await otpSend({ phone, role: 'rider' }).expect(200);
      const res = await api(app)
        .post('/v1/auth/otp/verify')
        .send({ phone, role: 'rider', code: '000001' })
        .expect(401);
      expect(res.body).toEqual({
        error: { code: 'OTP_INVALID', message: 'Invalid or expired code' },
      });
    });

    it('rejects the 6th OTP request for a phone within an hour', async () => {
      const phone = randomPhone();
      // Different client IPs so the per-IP limit (3/min) does not trigger first.
      for (let i = 1; i <= 5; i++) {
        await api(app)
          .post('/v1/auth/otp/send')
          .set('X-Forwarded-For', `10.9.0.${i}`)
          .send({ phone, role: 'rider' })
          .expect(200);
      }
      const sixth = await api(app)
        .post('/v1/auth/otp/send')
        .set('X-Forwarded-For', '10.9.0.6')
        .send({ phone, role: 'rider' })
        .expect(429);
      expect(sixth.body.error.code).toBe('OTP_RATE_LIMITED');
    });

    it('rejects the 4th OTP request from one IP within a minute', async () => {
      for (let i = 0; i < 3; i++) {
        await api(app)
          .post('/v1/auth/otp/send')
          .set('X-Forwarded-For', '10.8.0.1')
          .send({ phone: randomPhone(), role: 'rider' })
          .expect(200);
      }
      await api(app)
        .post('/v1/auth/otp/send')
        .set('X-Forwarded-For', '10.8.0.1')
        .send({ phone: randomPhone(), role: 'rider' })
        .expect(429);
    });

    it('rejects unknown body fields', async () => {
      const res = await otpSend({ phone: randomPhone(), role: 'rider', admin: true }).expect(400);
      expect(res.body.error.code).toBe('VALIDATION_FAILED');
    });

    it('rotates refresh tokens and revokes the family on reuse', async () => {
      const { refresh_token: r1 } = await login(randomPhone(), 'rider');
      const rotated = await api(app)
        .post('/v1/auth/refresh')
        .send({ refresh_token: r1 })
        .expect(200);
      const r2 = rotated.body.refresh_token;
      expect(r2).not.toBe(r1);

      const reuse = await api(app).post('/v1/auth/refresh').send({ refresh_token: r1 }).expect(401);
      expect(reuse.body.error.code).toBe('REFRESH_REUSED');
      // The legitimate newer token died with the family.
      await api(app).post('/v1/auth/refresh').send({ refresh_token: r2 }).expect(401);
    });

    it('logout clears the FCM token and revokes refresh tokens', async () => {
      const { access_token, refresh_token, user } = await login(randomPhone(), 'rider');
      await api(app).post('/v1/auth/logout').set(bearer(access_token)).expect(204);
      expect((await prisma.user.findUniqueOrThrow({ where: { id: user.id } })).fcmToken).toBeNull();
      await api(app).post('/v1/auth/refresh').send({ refresh_token }).expect(401);
    });

    it('delete account anonymises the user and keeps the row', async () => {
      const phone = randomPhone();
      const { access_token, refresh_token, user } = await login(phone, 'rider');
      await api(app).delete('/v1/me').set(bearer(access_token)).expect(204);
      const row = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
      expect(row.phone).toMatch(/^del:/);
      expect(row.phone.length).toBeLessThanOrEqual(15);
      expect(row).toMatchObject({ name: null, status: 'blocked' });
      await api(app).post('/v1/auth/refresh').send({ refresh_token }).expect(401);
      // The phone number is free to sign up again.
      const again = await login(phone, 'rider');
      expect(again.user.id).not.toBe(user.id);
    });

    it('refuses a rider phone in the driver app', async () => {
      const phone = randomPhone();
      await login(phone, 'rider');
      await otpSend({ phone, role: 'driver' }).expect(200);
      const res = await api(app)
        .post('/v1/auth/otp/verify')
        .send({ phone, role: 'driver', code: BYPASS })
        .expect(403);
      expect(res.body.error.code).toBe('ROLE_MISMATCH');
    });

    it('requires auth and enforces roles', async () => {
      await api(app).get('/v1/me').expect(401);
      await api(app).get('/v1/me').set(bearer('garbage')).expect(401);
      const { access_token } = await login(randomPhone(), 'rider');
      await api(app).get('/v1/driver/me').set(bearer(access_token)).expect(403);
      await api(app).get('/v1/admin/drivers').set(bearer(access_token)).expect(403);
    });
  });

  describe('admin login', () => {
    it('logs in and rejects a wrong password generically', async () => {
      await adminToken();
      const res = await api(app)
        .post('/v1/auth/admin/login')
        .send({ ...ADMIN, password: 'wrong' })
        .expect(401);
      expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
    });

    it('locks an account after 10 failures', async () => {
      const ghost = { email: `ghost-${Date.now()}@test.local`, password: 'x' };
      for (let i = 0; i < 10; i++)
        await api(app).post('/v1/auth/admin/login').send(ghost).expect(401);
      const res = await api(app).post('/v1/auth/admin/login').send(ghost).expect(429);
      expect(res.body.error.code).toBe('ACCOUNT_LOCKED');
    });
  });

  describe('driver onboarding and admin review', () => {
    const DOCS = [
      { doc_type: 'driving_licence', expiry: '2031-05-31' },
      { doc_type: 'rc' },
      { doc_type: 'insurance', expiry: '2027-03-31' },
      { doc_type: 'permit', expiry: '2028-01-15' },
      { doc_type: 'id_proof', id_last4: '4321' },
      { doc_type: 'selfie' },
    ] as const;

    let driverToken: string;
    let driverId: string;
    let admin: string;

    const upload = async (doc: (typeof DOCS)[number]) => {
      const presign = await api(app)
        .post('/v1/driver/documents/presign')
        .set(bearer(driverToken))
        .send({ doc_type: doc.doc_type, content_type: 'image/jpeg' })
        .expect(200);
      expect(presign.body.upload_url).toContain('X-Amz-Signature=');
      expect(presign.body.file_key).toMatch(
        new RegExp(`^drivers/${driverId}/${doc.doc_type}/.+\\.jpg$`),
      );
      const res = await api(app)
        .post('/v1/driver/documents')
        .set(bearer(driverToken))
        .send({ ...doc, file_key: presign.body.file_key })
        .expect(201);
      return res.body as { id: string; status: string };
    };

    const driverMe = async () =>
      (await api(app).get('/v1/driver/me').set(bearer(driverToken)).expect(200)).body;

    beforeAll(async () => {
      const session = await login(randomPhone(), 'driver');
      driverToken = session.access_token;
      driverId = session.user.id;
      admin = await adminToken();
    });

    it('a new driver starts pending and unregistered', async () => {
      const me = await driverMe();
      expect(me).toMatchObject({
        verification_status: 'pending',
        registered: false,
        can_go_online: false,
      });
      expect(me.missing_documents).toHaveLength(6);
    });

    it('registers profile and vehicle', async () => {
      const body = {
        name: 'Ravi Kumar',
        licence_no: 'dl04 2011 0012345',
        licence_expiry: '2031-05-31',
        date_of_birth: '1990-06-15',
        vehicle: {
          reg_number: 'dl 01 ab 1234',
          make: 'Maruti Suzuki',
          model: 'Dzire',
          colour: 'White',
          fuel_type: 'cng',
        },
      };
      const noDob: Partial<typeof body> = { ...body };
      delete noDob.date_of_birth;
      await api(app).post('/v1/driver/register').set(bearer(driverToken)).send(noDob).expect(400);
      // Under 18 today.
      const young = new Date();
      young.setUTCFullYear(young.getUTCFullYear() - 17);
      const tooYoung = await api(app)
        .post('/v1/driver/register')
        .set(bearer(driverToken))
        .send({ ...body, date_of_birth: young.toISOString().slice(0, 10) })
        .expect(422);
      expect(tooYoung.body.error.code).toBe('DATE_OF_BIRTH_INVALID');

      const res = await api(app)
        .post('/v1/driver/register')
        .set(bearer(driverToken))
        .send(body)
        .expect(200);
      expect(res.body).toMatchObject({
        name: 'Ravi Kumar',
        licence_no: 'DL0420110012345',
        date_of_birth: '1990-06-15',
        registered: true,
        vehicle: { reg_number: 'DL01AB1234', vehicle_type: 'sedan', fuel_type: 'cng' },
      });
    });

    it('validates document uploads', async () => {
      const presign = await api(app)
        .post('/v1/driver/documents/presign')
        .set(bearer(driverToken))
        .send({ doc_type: 'insurance', content_type: 'image/jpeg' })
        .expect(200);
      const noExpiry = await api(app)
        .post('/v1/driver/documents')
        .set(bearer(driverToken))
        .send({ doc_type: 'insurance', file_key: presign.body.file_key })
        .expect(422);
      expect(noExpiry.body.error.code).toBe('EXPIRY_REQUIRED');
      const expired = await api(app)
        .post('/v1/driver/documents')
        .set(bearer(driverToken))
        .send({ doc_type: 'insurance', file_key: presign.body.file_key, expiry: '2020-01-01' })
        .expect(422);
      expect(expired.body.error.code).toBe('DOCUMENT_EXPIRED');
      const foreign = await api(app)
        .post('/v1/driver/documents')
        .set(bearer(driverToken))
        .send({ doc_type: 'rc', file_key: 'drivers/someone-else/rc/x.jpg' })
        .expect(422);
      expect(foreign.body.error.code).toBe('INVALID_FILE_KEY');
      await api(app)
        .post('/v1/driver/documents/presign')
        .set(bearer(driverToken))
        .send({ doc_type: 'rc', content_type: 'text/html' })
        .expect(400);
    });

    it('uploads 6 documents and sees pending', async () => {
      for (const doc of DOCS) expect((await upload(doc)).status).toBe('pending');
      const me = await driverMe();
      expect(me.verification_status).toBe('pending');
      expect(me.documents).toHaveLength(6);
      expect(me.missing_documents).toEqual([]);
      const row = await prisma.driver.findUniqueOrThrow({ where: { userId: driverId } });
      expect(row.idLast4).toBe('4321');
      expect(row.selfieKey).toMatch(/selfie/);
    });

    it('admin sees the driver in the pending list with signed document URLs', async () => {
      const list = await api(app)
        .get('/v1/admin/drivers?status=pending&q=Ravi&limit=100')
        .set(bearer(admin))
        .expect(200);
      expect(list.body).toMatchObject({ page: 1, limit: 100 });
      const row = list.body.data.find((d: { user_id: string }) => d.user_id === driverId);
      expect(row).toMatchObject({
        verification_status: 'pending',
        reg_number: 'DL01AB1234',
        pending_documents: 6,
        licence_flagged: false,
      });

      const detail = await api(app)
        .get(`/v1/admin/drivers/${driverId}`)
        .set(bearer(admin))
        .expect(200);
      expect(detail.body.document_history).toHaveLength(6);
      for (const d of detail.body.document_history) {
        expect(d.view_url).toContain('X-Amz-Expires=300');
      }
      expect(detail.body.id_last4).toBe('4321');
      expect(detail.body.date_of_birth).toBe('1990-06-15');
      expect(detail.body.licence_check).toEqual({
        standard: true,
        state_code: 'DL',
        state: 'Delhi',
        rto_code: '04',
        issue_year: 2011,
        warnings: [],
      });
    });

    it('cannot approve the driver before the documents', async () => {
      const res = await api(app)
        .post(`/v1/admin/drivers/${driverId}/approve`)
        .set(bearer(admin))
        .send({})
        .expect(422);
      expect(res.body.error.code).toBe('DOCUMENTS_INCOMPLETE');
    });

    it('a rejected document shows the note to the driver, who can re-upload', async () => {
      const rc = (await driverMe()).documents.find(
        (d: { doc_type: string }) => d.doc_type === 'rc',
      );
      await api(app)
        .post(`/v1/admin/drivers/${driverId}/documents/${rc.id}/reject`)
        .set(bearer(admin))
        .send({ note: 'RC photo is blurry' })
        .expect(200);

      const me = await driverMe();
      expect(me.documents.find((d: { doc_type: string }) => d.doc_type === 'rc')).toMatchObject({
        status: 'rejected',
        reviewer_note: 'RC photo is blurry',
      });
      expect(me.missing_documents).toEqual(['rc']);

      await upload({ doc_type: 'rc' });
      expect((await driverMe()).missing_documents).toEqual([]);
    });

    it('admin approves every document, then the driver; the driver app sees approved', async () => {
      for (const doc of (await driverMe()).documents) {
        await api(app)
          .post(`/v1/admin/drivers/${driverId}/documents/${doc.id}/approve`)
          .set(bearer(admin))
          .send({})
          .expect(200);
      }
      const res = await api(app)
        .post(`/v1/admin/drivers/${driverId}/approve`)
        .set(bearer(admin))
        .send({ note: 'Welcome' })
        .expect(200);
      expect(res.body.verification_status).toBe('approved');

      const me = await driverMe();
      expect(me).toMatchObject({ verification_status: 'approved', can_go_online: true });

      const audits = await prisma.auditLog.findMany({
        where: { entityId: driverId, action: 'driver.approve' },
      });
      expect(audits).toHaveLength(1);
    });

    it('rejects invalid transitions, and suspend/reinstate works', async () => {
      const again = await api(app)
        .post(`/v1/admin/drivers/${driverId}/approve`)
        .set(bearer(admin))
        .send({})
        .expect(409);
      expect(again.body.error.code).toBe('INVALID_TRANSITION');

      await api(app)
        .post(`/v1/admin/drivers/${driverId}/suspend`)
        .set(bearer(admin))
        .send({ note: 'Complaint' })
        .expect(200);
      expect(await driverMe()).toMatchObject({
        verification_status: 'suspended',
        can_go_online: false,
      });
      await api(app)
        .post(`/v1/admin/drivers/${driverId}/reinstate`)
        .set(bearer(admin))
        .send({})
        .expect(200);
      expect(await driverMe()).toMatchObject({
        verification_status: 'approved',
        can_go_online: true,
      });
    });

    it('an approved driver cannot silently re-register', async () => {
      const res = await api(app)
        .post('/v1/driver/register')
        .set(bearer(driverToken))
        .send({
          name: 'X',
          licence_no: 'DL0420110012345',
          licence_expiry: '2031-05-31',
          date_of_birth: '1990-06-15',
          vehicle: {
            reg_number: 'DL01AB9999',
            make: 'A',
            model: 'B',
            colour: 'C',
            fuel_type: 'petrol',
          },
        })
        .expect(409);
      expect(res.body.error.code).toBe('ALREADY_REGISTERED');
    });

    it('admin edits the vehicle (audited)', async () => {
      const res = await api(app)
        .patch(`/v1/admin/drivers/${driverId}/vehicle`)
        .set(bearer(admin))
        .send({ colour: 'Silver' })
        .expect(200);
      expect(res.body).toMatchObject({ colour: 'Silver', reg_number: 'DL01AB1234' });
      expect(
        await prisma.auditLog.count({ where: { action: 'vehicle.update', entity: 'vehicle' } }),
      ).toBeGreaterThan(0);
    });
  });
});
