import RedisMock from 'ioredis-mock';
import type { Env } from '../../config/env.schema';
import type { RedisService } from '../../common/redis.service';
import { RoutingService } from './routing.service';

const A = { lat: 28.6315, lng: 77.2167 };
const B = { lat: 28.4595, lng: 77.0266 };
const json = (status: number, body: unknown) => ({
  ok: status < 400,
  status,
  json: async () => body,
});

describe('RoutingService', () => {
  let fetchMock: jest.Mock;
  const make = (google?: string) =>
    new RoutingService(
      new RedisMock() as unknown as RedisService,
      {
        OSRM_BASE_URL: 'http://osrm:5000',
        GOOGLE_MAPS_SERVER_KEY: google,
      } as Env,
    );

  beforeEach(async () => {
    await new RedisMock().flushall();
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  it('uses OSRM with lng,lat order and caches the result', async () => {
    fetchMock.mockResolvedValue(
      json(200, { code: 'Ok', routes: [{ distance: 28123.6, duration: 2400.2 }] }),
    );
    const svc = make();
    await expect(svc.route(A, B)).resolves.toEqual({ distance_m: 28124, duration_s: 2400 });
    expect(fetchMock.mock.calls[0][0]).toBe(
      'http://osrm:5000/route/v1/driving/77.2167,28.6315;77.0266,28.4595?overview=false',
    );
    await svc.route(A, B);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('falls back to the Google Routes API (traffic-aware) when OSRM fails', async () => {
    fetchMock
      .mockRejectedValueOnce(new Error('timeout'))
      .mockResolvedValueOnce(json(200, { routes: [{ distanceMeters: 30000, duration: '3100s' }] }));
    await expect(make('gkey').route(A, B)).resolves.toEqual({
      distance_m: 30000,
      duration_s: 3100,
    });
    const [url, init] = fetchMock.mock.calls[1] as [string, RequestInit];
    expect(url).toBe('https://routes.googleapis.com/directions/v2:computeRoutes');
    expect(init.headers).toMatchObject({
      'X-Goog-Api-Key': 'gkey',
      'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration',
    });
    expect(JSON.parse(init.body as string)).toEqual({
      origin: { location: { latLng: { latitude: 28.6315, longitude: 77.2167 } } },
      destination: { location: { latLng: { latitude: 28.4595, longitude: 77.0266 } } },
      travelMode: 'DRIVE',
      routingPreference: 'TRAFFIC_AWARE',
    });
  });

  it('Routes API: an empty or failed response counts as a failure', async () => {
    fetchMock
      .mockRejectedValueOnce(new Error('down'))
      .mockResolvedValueOnce(json(200, {}))
      .mockRejectedValueOnce(new Error('down'))
      .mockResolvedValueOnce(json(403, { error: { status: 'PERMISSION_DENIED' } }));
    const svc = make('gkey');
    await expect(svc.route(A, B)).rejects.toMatchObject({ code: 'ROUTING_UNAVAILABLE' });
    await expect(svc.route(A, B)).rejects.toMatchObject({ code: 'ROUTING_UNAVAILABLE' });
  });

  it('returns 503 ROUTING_UNAVAILABLE when both fail', async () => {
    fetchMock.mockResolvedValue(json(500, { code: 'Error' }));
    await expect(make('gkey').route(A, B)).rejects.toMatchObject({ code: 'ROUTING_UNAVAILABLE' });
    await expect(make().route(A, B)).rejects.toMatchObject({ code: 'ROUTING_UNAVAILABLE' });
  });
});
