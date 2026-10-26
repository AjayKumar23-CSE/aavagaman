import { createServer, Server } from 'node:http';

/** Minimal OSRM stand-in: road distance ≈ 1.3 × straight line, 7 m/s average. */
export const FAKE_OSRM_PORT = 5055;

function haversineM(lat1: number, lng1: number, lat2: number, lng2: number) {
  const r = (d: number) => (d * Math.PI) / 180;
  const h =
    Math.sin(r(lat2 - lat1) / 2) ** 2 +
    Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lng2 - lng1) / 2) ** 2;
  return 2 * 6_371_000 * Math.asin(Math.sqrt(h));
}

export function startFakeOsrm(): Promise<Server> {
  const server = createServer((req, res) => {
    const m = /^\/route\/v1\/driving\/([-\d.]+),([-\d.]+);([-\d.]+),([-\d.]+)/.exec(req.url ?? '');
    res.setHeader('content-type', 'application/json');
    if (m) {
      const [lng1, lat1, lng2, lat2] = m.slice(1).map(Number);
      const distance = haversineM(lat1, lng1, lat2, lng2) * 1.3;
      res.end(JSON.stringify({ code: 'Ok', routes: [{ distance, duration: distance / 7 }] }));
      return;
    }
    if (req.url?.startsWith('/nearest/')) {
      res.end(JSON.stringify({ code: 'Ok', waypoints: [] }));
      return;
    }
    res.statusCode = 400;
    res.end(JSON.stringify({ code: 'InvalidUrl' }));
  });
  return new Promise((resolve) => server.listen(FAKE_OSRM_PORT, () => resolve(server)));
}
