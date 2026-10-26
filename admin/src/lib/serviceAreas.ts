import type { Feature, FeatureCollection, Polygon } from 'geojson';
import { api, patchJson, postJson } from './api';

export interface ServiceAreaProps {
  id: string;
  name: string;
  active: boolean;
  created_at: string | null;
}

/** The area id is duplicated in `properties.id` (GeoJSON `Feature.id` is loosely typed). */
export type ServiceArea = Feature<Polygon, ServiceAreaProps>;
export type ServiceAreaCollection = FeatureCollection<Polygon, ServiceAreaProps>;

export function listServiceAreas(): Promise<ServiceAreaCollection> {
  return api('/v1/admin/service-areas');
}

export function createServiceArea(body: { name: string; polygon: Polygon; active?: boolean }): Promise<ServiceArea> {
  return postJson('/v1/admin/service-areas', body);
}

export function patchServiceArea(
  id: string,
  patch: { name?: string; polygon?: Polygon; active?: boolean },
): Promise<ServiceArea> {
  return patchJson(`/v1/admin/service-areas/${encodeURIComponent(id)}`, patch);
}

function isPolygon(g: unknown): g is Polygon {
  const p = g as Polygon | null;
  return (
    !!p &&
    p.type === 'Polygon' &&
    Array.isArray(p.coordinates) &&
    p.coordinates.length > 0 &&
    p.coordinates.every((ring) => Array.isArray(ring) && ring.every((c) => Array.isArray(c) && c.length >= 2))
  );
}

/**
 * Accepts the GeoJSON shapes an admin is likely to export from QGIS / geojson.io:
 * a bare Polygon, a Feature wrapping one, or a FeatureCollection with exactly one Polygon.
 */
export function extractPolygon(input: unknown): Polygon {
  const obj = input as { type?: string; geometry?: unknown; features?: { geometry?: unknown }[] } | null;
  if (!obj || typeof obj !== 'object') throw new Error('Not a GeoJSON object');
  if (obj.type === 'Polygon') {
    if (!isPolygon(obj)) throw new Error('Polygon coordinates are malformed');
    return obj as Polygon;
  }
  if (obj.type === 'Feature') {
    if (!isPolygon(obj.geometry)) throw new Error('The feature geometry must be a Polygon');
    return obj.geometry;
  }
  if (obj.type === 'FeatureCollection') {
    const polys = (obj.features ?? []).map((f) => f.geometry).filter(isPolygon);
    if (polys.length !== 1)
      throw new Error(
        polys.length === 0
          ? 'The collection has no Polygon feature'
          : `The collection has ${polys.length} polygons; import one at a time`,
      );
    return polys[0];
  }
  throw new Error(`Unsupported GeoJSON type "${obj.type ?? 'unknown'}"; expected Polygon, Feature or FeatureCollection`);
}
