/**
 * Creates load-test accounts on a dev/staging API (OTP bypass required) and writes
 * test/load/accounts.json for ride-load.js. Not part of the Jest suites.
 */
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const BASE = (process.env.API_BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '');
const BYPASS = process.env.OTP_DEV_BYPASS_CODE ?? '123456';
const DRIVERS = Number(process.env.LOAD_DRIVERS ?? 100);
const RIDERS = Number(process.env.LOAD_RIDERS ?? 50);
const DOCS = [
  { doc_type: 'driving_licence', expiry: '2031-05-31' },
  { doc_type: 'rc' },
  { doc_type: 'insurance', expiry: '2028-03-31' },
  { doc_type: 'permit', expiry: '2028-01-15' },
  { doc_type: 'id_proof', id_last4: '0000' },
  { doc_type: 'selfie' },
];

let ipSeq = 0;
async function call<T>(path: string, init: RequestInit & { token?: string } = {}): Promise<T> {
  const res = await fetch(`${BASE}/v1${path}`, {
    ...init,
    headers: {
      'content-type': 'application/json',
      // Spread OTP sends over client IPs so the 3/min per-IP limit does not bite.
      'x-forwarded-for': `10.77.${Math.floor(ipSeq / 250)}.${1 + (ipSeq++ % 250)}`,
      ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
      ...(init.headers as Record<string, string> | undefined),
    },
  });
  if (res.status === 204) return undefined as T;
  const body = await res.json();
  if (!res.ok) throw new Error(`${init.method ?? 'GET'} ${path} → ${res.status} ${JSON.stringify(body)}`);
  return body as T;
}

const phone = () => '+9177' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');

async function login(role: 'rider' | 'driver') {
  const p = phone();
  await call('/auth/otp/send', { method: 'POST', body: JSON.stringify({ phone: p, role }) });
  const r = await call<{ access_token: string; user: { id: string } }>('/auth/otp/verify', {
    method: 'POST',
    body: JSON.stringify({ phone: p, role, code: BYPASS, device: { platform: 'k6' } }),
  });
  return { phone: p, token: r.access_token, id: r.user.id };
}

async function main() {
  const admin = await call<{ access_token: string }>('/auth/admin/login', {
    method: 'POST',
    body: JSON.stringify({ email: process.env.ADMIN_EMAIL ?? 'admin@ride.local', password: process.env.ADMIN_PASSWORD ?? 'admin12345' }),
  });
  const drivers = [];
  for (let i = 0; i < DRIVERS; i++) {
    const d = await login('driver');
    await call('/driver/register', {
      method: 'POST',
      token: d.token,
      body: JSON.stringify({
        name: `Load Driver ${i}`,
        licence_no: `LD${String(i).padStart(8, '0')}`,
        licence_expiry: '2031-05-31',
        date_of_birth: '1990-06-15',
        vehicle: { reg_number: `DL${String(10 + (i % 90))}LD${String(i).padStart(4, '0')}`, make: 'Maruti Suzuki', model: 'Dzire', colour: 'White', fuel_type: 'cng' },
      }),
    });
    for (const doc of DOCS) {
      const pre = await call<{ file_key: string }>('/driver/documents/presign', { method: 'POST', token: d.token, body: JSON.stringify({ doc_type: doc.doc_type, content_type: 'image/jpeg' }) });
      const created = await call<{ id: string }>('/driver/documents', { method: 'POST', token: d.token, body: JSON.stringify({ ...doc, file_key: pre.file_key }) });
      await call(`/admin/drivers/${d.id}/documents/${created.id}/approve`, { method: 'POST', token: admin.access_token, body: '{}' });
    }
    await call(`/admin/drivers/${d.id}/approve`, { method: 'POST', token: admin.access_token, body: '{}' });
    drivers.push(d);
    if (i % 10 === 9) console.log(`drivers: ${i + 1}/${DRIVERS}`);
  }
  const riders = [];
  for (let i = 0; i < RIDERS; i++) riders.push(await login('rider'));
  const out = resolve(__dirname, 'accounts.json');
  writeFileSync(out, JSON.stringify({ base: BASE, drivers, riders }, null, 2));
  console.log(`wrote ${out}: ${drivers.length} drivers, ${riders.length} riders`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
