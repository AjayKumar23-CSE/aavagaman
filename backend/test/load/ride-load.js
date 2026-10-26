// k6 script (SPEC §19). Requires accounts.json from seed.ts.
//   k6 run test/load/ride-load.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';
import { Counter, Trend } from 'k6/metrics';

const accounts = new SharedArray('accounts', () => [JSON.parse(open('./accounts.json'))]);
const A = accounts[0];
const BASE = (__ENV.API_BASE_URL || A.base).replace(/\/$/, '') + '/v1';

const offersDropped = new Counter('ride_requests_without_offer');
const requestLatency = new Trend('ride_request_ms', true);

export const options = {
  scenarios: {
    drivers: {
      executor: 'per-vu-iterations',
      vus: A.drivers.length,
      iterations: 1,
      maxDuration: '11m',
      exec: 'driver',
    },
    riders: {
      executor: 'constant-arrival-rate',
      rate: 5,
      timeUnit: '1m',
      duration: '10m',
      preAllocatedVUs: 10,
      exec: 'rider',
      startTime: '20s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01'],
    ride_requests_without_offer: ['count==0'],
  },
};

// Spread drivers over central Delhi so most pickups have someone within 3 km.
const CENTER = { lat: 28.6315, lng: 77.2167 };
const jitter = (km) => (Math.random() - 0.5) * 2 * (km / 111);
const auth = (token) => ({ headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` } });

export function driver() {
  const me = A.drivers[__VU - 1];
  const pos = { lat: CENTER.lat + jitter(6), lng: CENTER.lng + jitter(6) };
  const on = http.post(`${BASE}/driver/online`, JSON.stringify(pos), auth(me.token));
  check(on, { 'online 204': (r) => r.status === 204 });
  const until = Date.now() + 10 * 60 * 1000;
  while (Date.now() < until) {
    pos.lat += jitter(0.05);
    pos.lng += jitter(0.05);
    // REST fallback path for location ingest (the apps use the WebSocket).
    const r = http.post(`${BASE}/driver/location`, JSON.stringify({ ...pos, heading: 90, speed: 8, accuracy: 6 }), auth(me.token));
    check(r, { 'location 204': (x) => x.status === 204 });
    // Accept whatever offer is pending so rides keep flowing.
    const active = http.get(`${BASE}/driver/rides/active`, auth(me.token));
    if (active.status === 200) {
      const ride = active.json();
      if (ride.status === 'COMPLETED') http.post(`${BASE}/driver/rides/${ride.id}/cash-collected`, null, auth(me.token));
    }
    sleep(4);
  }
  http.post(`${BASE}/driver/offline`, null, auth(me.token));
}

export function rider() {
  const me = A.riders[Math.floor(Math.random() * A.riders.length)];
  const pickup = { lat: CENTER.lat + jitter(4), lng: CENTER.lng + jitter(4), address: 'Load pickup' };
  const drop = { lat: CENTER.lat + jitter(8), lng: CENTER.lng + jitter(8), address: 'Load drop' };
  const est = http.post(`${BASE}/fare/estimate`, JSON.stringify({ pickup, drop }), auth(me.token));
  if (!check(est, { 'estimate 200': (r) => r.status === 200 })) return;
  const t0 = Date.now();
  const ride = http.post(
    `${BASE}/rides`,
    JSON.stringify({ pickup, drop, fare_config_id: est.json().fare_config_id, payment_method: 'cash' }),
    auth(me.token),
  );
  requestLatency.add(Date.now() - t0);
  if (!check(ride, { 'ride 201': (r) => r.status === 201 })) return;
  const id = ride.json().id;
  // An offer must reach some driver within the 2-minute matching window.
  sleep(25);
  const after = http.get(`${BASE}/rides/${id}`, auth(me.token));
  const status = after.status === 200 ? after.json().status : 'UNKNOWN';
  if (status === 'REQUESTED' || status === 'NO_DRIVER') offersDropped.add(1);
  // Keep the rider free for the next request.
  if (status === 'REQUESTED' || status === 'ACCEPTED') http.post(`${BASE}/rides/${id}/cancel`, '{}', auth(me.token));
}
