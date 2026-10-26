export interface LatLng {
  lat: number;
  lng: number;
}

const R = 6_371_000; // mean Earth radius, metres
const rad = (d: number) => (d * Math.PI) / 180;

/** Great-circle distance in metres. */
export function haversineM(a: LatLng, b: LatLng): number {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** WKT for PostGIS: POINT(lng lat). */
export const toWkt = (p: LatLng) => `SRID=4326;POINT(${p.lng} ${p.lat})`;
