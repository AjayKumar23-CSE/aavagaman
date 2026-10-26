import { useMemo } from 'react';
import type { LatLngBoundsExpression } from 'leaflet';
import { CircleMarker, Polyline, Tooltip } from 'react-leaflet';
import LeafletMap, { FitBoundsOnce, InvalidateOnMount } from '../../components/LeafletMap';
import type { Ride, RideTrack } from '../../lib/rides';

const TRACK_COLOUR = '#2563eb';

/** Pickup/drop plus the recorded GPS track (GeoJSON LineString, [lng, lat]). */
export default function RideMap({ ride, track }: { ride: Ride; track: RideTrack }) {
  const { lat: pLat, lng: pLng } = ride.pickup;
  const { lat: dLat, lng: dLng } = ride.drop;
  const { path, pickup, drop, bounds } = useMemo(() => {
    const path: [number, number][] = track.geometry.coordinates.map(([lng, lat]) => [lat, lng]);
    const pickup: [number, number] = [pLat, pLng];
    const drop: [number, number] = [dLat, dLng];
    const bounds: LatLngBoundsExpression = [pickup, drop, ...path];
    return { path, pickup, drop, bounds };
  }, [track, pLat, pLng, dLat, dLng]);

  return (
    <div className="relative h-80 overflow-hidden rounded-b-lg">
      <LeafletMap className="h-full w-full">
        <InvalidateOnMount />
        <FitBoundsOnce bounds={bounds} />
        <Polyline positions={[pickup, drop]} pathOptions={{ color: '#9ca3af', weight: 2, dashArray: '6 6' }} />
        {path.length > 1 && <Polyline positions={path} pathOptions={{ color: TRACK_COLOUR, weight: 4, opacity: 0.9 }} />}
        {path.length > 0 && (
          <CircleMarker center={path[path.length - 1]} radius={5} pathOptions={{ color: '#fff', weight: 2, fillColor: TRACK_COLOUR, fillOpacity: 1 }}>
            <Tooltip>Last fix</Tooltip>
          </CircleMarker>
        )}
        <CircleMarker center={pickup} radius={7} pathOptions={{ color: '#fff', weight: 2, fillColor: '#111827', fillOpacity: 1 }}>
          <Tooltip permanent direction="right" offset={[8, 0]}>
            Pickup
          </Tooltip>
        </CircleMarker>
        <CircleMarker center={drop} radius={7} pathOptions={{ color: '#fff', weight: 2, fillColor: '#dc2626', fillOpacity: 1 }}>
          <Tooltip permanent direction="right" offset={[8, 0]}>
            Drop
          </Tooltip>
        </CircleMarker>
      </LeafletMap>
      <div className="absolute right-3 bottom-3 z-[400] rounded-md border border-gray-200 bg-white/95 px-3 py-1.5 text-xs text-gray-700">
        {track.properties.points > 0 ? `${track.properties.points} GPS points` : 'No GPS track recorded'}
      </div>
    </div>
  );
}
