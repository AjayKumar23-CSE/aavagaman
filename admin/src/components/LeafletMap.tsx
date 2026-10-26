import { useEffect, useRef, type ReactNode } from 'react';
import type { LatLngBoundsExpression, LatLngExpression } from 'leaflet';
import { MapContainer, TileLayer, useMap } from 'react-leaflet';

/** SPEC §13 / §21: the service runs in Delhi NCR; maps open on Connaught Place. */
const DELHI_CENTER: LatLngExpression = [28.6315, 77.2167];

const OSM_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const OSM_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

interface Props {
  children?: ReactNode;
  className?: string;
  center?: LatLngExpression;
  zoom?: number;
}

/** OSM-tiled Leaflet map; the parent must give it a height (via className). */
export default function LeafletMap({ children, className = 'h-full w-full', center = DELHI_CENTER, zoom = 11 }: Props) {
  return (
    <MapContainer center={center} zoom={zoom} scrollWheelZoom className={className}>
      <TileLayer url={OSM_URL} attribution={OSM_ATTRIBUTION} />
      {children}
    </MapContainer>
  );
}

/** Fits the view to `bounds` the first time they become available, then leaves the admin's panning alone. */
export function FitBoundsOnce({ bounds }: { bounds: LatLngBoundsExpression | null }) {
  const map = useMap();
  const done = useRef(false);
  useEffect(() => {
    if (done.current || !bounds) return;
    done.current = true;
    map.fitBounds(bounds, { padding: [32, 32], maxZoom: 15 });
  }, [bounds, map]);
  return null;
}

/** Pans/zooms to `target` whenever it changes (pass a new object to re-trigger). */
export function FlyTo({ target }: { target: { lat: number; lng: number } | null }) {
  const map = useMap();
  useEffect(() => {
    if (target) map.flyTo([target.lat, target.lng], Math.max(map.getZoom(), 14), { duration: 0.6 });
  }, [target, map]);
  return null;
}

/** Leaflet measures its container on mount; this re-measures after layout settles (flex/grid parents). */
export function InvalidateOnMount() {
  const map = useMap();
  useEffect(() => {
    const t = setTimeout(() => map.invalidateSize(), 50);
    return () => clearTimeout(t);
  }, [map]);
  return null;
}
