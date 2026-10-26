import { NestExpressApplication } from '@nestjs/platform-express';
import { api, randomIp, randomPhone } from './app';

export const BYPASS = '123456';
export const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

export interface Session {
  token: string;
  id: string;
}

export async function loginAs(
  app: NestExpressApplication,
  role: 'rider' | 'driver',
  phone = randomPhone(),
): Promise<Session> {
  await api(app)
    .post('/v1/auth/otp/send')
    .set('X-Forwarded-For', randomIp())
    .send({ phone, role })
    .expect(200);
  const res = await api(app)
    .post('/v1/auth/otp/verify')
    .send({ phone, role, code: BYPASS })
    .expect(200);
  return { token: res.body.access_token, id: res.body.user.id };
}

export async function adminLogin(app: NestExpressApplication): Promise<string> {
  const res = await api(app)
    .post('/v1/auth/admin/login')
    .send({ email: 'admin@test.local', password: 'admin12345' })
    .expect(200);
  return res.body.access_token;
}

const DOCS = [
  { doc_type: 'driving_licence', expiry: '2031-05-31' },
  { doc_type: 'rc' },
  { doc_type: 'insurance', expiry: '2027-03-31' },
  { doc_type: 'permit', expiry: '2028-01-15' },
  { doc_type: 'id_proof', id_last4: '4321' },
  { doc_type: 'selfie' },
];

/** A fully onboarded, admin-approved driver. */
export async function approvedDriver(
  app: NestExpressApplication,
  admin: string,
  name = 'Test Driver',
  vehicleType = 'sedan',
): Promise<Session> {
  const s = await loginAs(app, 'driver');
  const reg =
    'DL' +
    String(Math.floor(Math.random() * 1e8))
      .padStart(8, '0')
      .slice(0, 2) +
    'AB' +
    String(Math.floor(Math.random() * 1e4)).padStart(4, '0');
  await api(app)
    .post('/v1/driver/register')
    .set(bearer(s.token))
    .send({
      name,
      licence_no: 'DL0420110012345',
      licence_expiry: '2031-05-31',
      date_of_birth: '1990-06-15',
      vehicle: {
        reg_number: reg,
        make: 'Maruti Suzuki',
        model: 'Dzire',
        colour: 'White',
        fuel_type: 'cng',
        vehicle_type: vehicleType,
      },
    })
    .expect(200);
  for (const doc of DOCS) {
    const p = await api(app)
      .post('/v1/driver/documents/presign')
      .set(bearer(s.token))
      .send({ doc_type: doc.doc_type, content_type: 'image/jpeg' })
      .expect(200);
    const d = await api(app)
      .post('/v1/driver/documents')
      .set(bearer(s.token))
      .send({ ...doc, file_key: p.body.file_key })
      .expect(201);
    await api(app)
      .post(`/v1/admin/drivers/${s.id}/documents/${d.body.id}/approve`)
      .set(bearer(admin))
      .send({})
      .expect(200);
  }
  await api(app).post(`/v1/admin/drivers/${s.id}/approve`).set(bearer(admin)).send({}).expect(200);
  return s;
}

// Delhi landmarks
export const CP = { lat: 28.6315, lng: 77.2167, address: 'Connaught Place, New Delhi' };
export const INDIA_GATE = { lat: 28.6129, lng: 77.2295, address: 'India Gate, New Delhi' };
export const MEERUT = { lat: 28.98, lng: 77.7, address: 'Meerut (outside NCR)' };
export const GREATER_NOIDA = { lat: 28.4744, lng: 77.504, address: 'Pari Chowk, Greater Noida' };
/** ~500 m and ~1.5 km north of CP. */
export const NEAR_CP = { lat: 28.636, lng: 77.2167 };
export const FARTHER_CP = { lat: 28.645, lng: 77.2167 };
