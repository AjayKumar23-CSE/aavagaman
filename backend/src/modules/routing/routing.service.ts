import { HttpStatus, Inject, Injectable, Logger } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import type { LatLng } from '../../common/geo/geo';
import { RedisService } from '../../common/redis.service';

export interface Route {
  distance_m: number;
  duration_s: number;
}

export const ROUTE_TIMEOUT_MS = 2000;
export const ROUTE_CACHE_SECONDS = 60;
const r4 = (n: number) => n.toFixed(4);

/** SPEC §9.2: OSRM first, Google (Routes API) on error/timeout, cached 60 s. */
@Injectable()
export class RoutingService {
  private readonly logger = new Logger(RoutingService.name);

  constructor(
    private readonly redis: RedisService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  async route(from: LatLng, to: LatLng): Promise<Route> {
    const key = `route:${r4(from.lat)},${r4(from.lng)};${r4(to.lat)},${r4(to.lng)}`;
    const cached = await this.redis.get(key);
    if (cached) return JSON.parse(cached) as Route;

    let route: Route | undefined;
    try {
      route = await this.osrm(from, to);
    } catch (err) {
      this.logger.warn(`OSRM failed: ${(err as Error).message}`);
      if (this.config.GOOGLE_MAPS_SERVER_KEY) {
        try {
          route = await this.google(from, to, this.config.GOOGLE_MAPS_SERVER_KEY);
        } catch (gErr) {
          this.logger.error(`Google Routes failed: ${(gErr as Error).message}`);
        }
      }
    }
    if (!route) {
      throw new AppException(
        'ROUTING_UNAVAILABLE',
        'Route could not be calculated. Try again.',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    await this.redis.set(key, JSON.stringify(route), 'EX', ROUTE_CACHE_SECONDS);
    return route;
  }

  private async osrm(from: LatLng, to: LatLng): Promise<Route> {
    const url = `${this.config.OSRM_BASE_URL}/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}?overview=false`;
    const res = await fetch(url, { signal: AbortSignal.timeout(ROUTE_TIMEOUT_MS) });
    const body = (await res.json()) as {
      code?: string;
      routes?: { distance: number; duration: number }[];
    };
    if (!res.ok || body.code !== 'Ok' || !body.routes?.length)
      throw new Error(`OSRM ${res.status} ${body.code}`);
    return {
      distance_m: Math.round(body.routes[0].distance),
      duration_s: Math.round(body.routes[0].duration),
    };
  }

  /**
   * Google Routes API (`computeRoutes`), traffic-aware like the Directions
   * `duration_in_traffic` it replaces: the legacy Directions API cannot be
   * enabled on new Cloud projects (D-052). Zero-valued fields are omitted in
   * the response, so a missing distance means 0.
   */
  private async google(from: LatLng, to: LatLng, key: string): Promise<Route> {
    const point = (p: LatLng) => ({ location: { latLng: { latitude: p.lat, longitude: p.lng } } });
    const res = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration',
      },
      body: JSON.stringify({
        origin: point(from),
        destination: point(to),
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_AWARE',
      }),
      signal: AbortSignal.timeout(ROUTE_TIMEOUT_MS),
    });
    const body = (await res.json()) as {
      routes?: { distanceMeters?: number; duration?: string }[];
      error?: { status?: string };
    };
    const route = body.routes?.[0];
    if (!res.ok || !route)
      throw new Error(`Routes API ${res.status} ${body.error?.status ?? 'NO_ROUTE'}`);
    return {
      distance_m: route.distanceMeters ?? 0,
      duration_s: Math.round(parseFloat(route.duration ?? '0')),
    };
  }
}
