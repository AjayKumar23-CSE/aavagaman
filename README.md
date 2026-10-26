# Aavagaman — Delhi NCR ride-hailing

*Safar • Aapke Saath.* Brand assets (logo, icons, palette) are in `docs/branding/`; the mark is drawn in code in `apps/shared/lib/src/widgets/brand.dart` (D-057).

Rider app, driver app, admin panel and backend. **SPEC.md is the contract**; decisions that deviate from it are in [docs/DECISIONS.md](docs/DECISIONS.md).

| Path | What |
|---|---|
| `backend/` | NestJS 12 API + Socket.io gateway (`dist/main.js`) and BullMQ worker (`dist/worker.js`), Prisma + PostGIS, Redis |
| `apps/shared/` | Flutter package: API client, models, theme |
| `apps/rider/`, `apps/driver/` | Flutter apps (Android first) |
| `admin/` | React + Vite admin panel |
| `infra/` | Dev and production Docker Compose, Caddyfile, OSRM scripts, backup image, seed polygon |
| `docs/` | [DECISIONS](docs/DECISIONS.md) · [RUNBOOK](docs/RUNBOOK.md) · [ADMIN_GUIDE](docs/ADMIN_GUIDE.md) · [PLAY_STORE](docs/PLAY_STORE.md) |

**Current phase:** 5 — Hardening and release (backend complete through Phase 5 ops items; app and admin-panel screens for Phases 2–4 in progress). See [CHANGELOG.md](CHANGELOG.md).

## Prerequisites
Docker Desktop, Node 22, Flutter stable (3.44 or later) with the Android SDK.

## Backend + infra

```bash
docker compose -f infra/docker-compose.yml up --build
curl localhost:3000/health            # {"status":"ok","db":true,"redis":true,"osrm":true}
open http://localhost:3000/docs       # Swagger
```

Seeded admin (dev only): `admin@ride.local` / `admin12345`. Dev OTP bypass code: `123456`.

Running the API on the host instead (Postgres, Redis and OSRM still in Docker):

```bash
docker compose -f infra/docker-compose.yml up -d postgres redis osrm
cd backend
cp .env.example .env    # then set: NODE_ENV=development, localhost URLs, OTP_DEV_BYPASS_CODE=123456
npm install && npx prisma migrate deploy && npm run seed
npm run start:dev                    # API; in a second terminal:
npm run build && node dist/worker.js # matching jobs + heartbeat sweeper
```

Nothing is matched without the worker: ride requests stay `REQUESTED` until it runs.

Tests: `npm test` (unit), `npm run test:e2e` (reads `backend/.env.test`; needs a migrated + seeded test database and Redis), `npm run lint`.

## Admin panel

```bash
cd admin
cp .env.example .env
npm install && npm run dev            # http://localhost:5173
```

To reach the panel from outside this machine during phone testing (D-054), build it against the API's public address and serve that build:

```bash
VITE_API_BASE_URL=https://<api-tunnel-host> npm run build
npm run preview                                        # http://localhost:4173; ngrok hostnames are allowed
ngrok http 127.0.0.1:4173 --url=<admin-tunnel-host>    # a second ngrok account: one free domain per account
```

Then add the panel's tunnel origin to the backend's `ADMIN_ORIGIN` (comma-separated). Behind ngrok's free tier the panel sends `ngrok-skip-browser-warning` on its API calls by itself.

## Mobile apps

`apps/shared` (API client, models, realtime, auth screens, the design system: theme, fonts and reusable widgets), `apps/rider` and `apps/driver`. The Android platform folders are committed. In each of the three:

```bash
flutter pub get && flutter analyze && flutter test
flutter run --dart-define=API_BASE_URL=http://<your-LAN-IP>:3000   # real phone
```

The default `API_BASE_URL` is `http://10.0.2.2:3000`, which is the Android emulator's address for the host machine. Debug builds allow plain HTTP (debug manifest only); release builds are HTTPS-only (SPEC §16).

Flavors (SPEC §17.5): `dev` (the default, package suffix `.dev`, for staging) and `prod`. Release builds are signed with the upload key from `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; gitignored) or the `KEYSTORE_PATH`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` variables, and fall back to the debug key when neither is set. CI builds signed `prod` AAB/APK on tags `rider-v*` / `driver-v*` (see `.github/workflows/apps.yml` and [docs/PLAY_STORE.md](docs/PLAY_STORE.md)).

```bash
flutter build appbundle --release --flavor prod \
  --dart-define=APP_ENV=prod --dart-define=API_BASE_URL=https://api.<domain> --dart-define=GOOGLE_MAPS_API_KEY=<key>
```

Google Maps on Android also needs `MAPS_API_KEY=<key>` in `android/local.properties` (or the environment).

To see the screens without a phone: `RIDE_SHOTS=/tmp/shots flutter test --update-goldens test/screenshots` in `apps/rider` or `apps/driver` writes a PNG of every main screen (real fonts, a stylised map).

Building needs JDK 17+ (21 is used) and the Android SDK with platforms 36 and 37, build-tools and NDK 28.2. Point Flutter at them once with `flutter config --jdk-dir <jdk> --android-sdk <sdk>`, then run `flutter doctor`.

## Operations

Production runs from `infra/docker-compose.prod.yml` behind Caddy; deploy, rollback, backups, staging and incident steps are in [docs/RUNBOOK.md](docs/RUNBOOK.md). Useful URLs on a running API:

| URL | What |
|---|---|
| `GET /health` | `{status, db, redis, osrm}`; 503 when db or redis is down |
| `GET /metrics` | Prometheus text; needs `METRICS_TOKEN` |
| `GET /docs` | Swagger (always in dev; `ENABLE_DOCS=true` in production) |
| `GET /v1/share/<token>` | Public trip-tracking page (JSON for apps) |
| `GET /v1/legal/privacy` | Privacy policy page (fill in the company details in `backend/src/modules/legal/privacy.page.ts`) |

### Masked calling (one Aavagaman number for rider ↔ driver calls)

Calls are bridged through a cloud-telephony number so neither party sees the other's phone (D-058). The code talks to [Exotel](https://exotel.com); `CALL_PROVIDER=stub` exercises the whole flow without placing calls, `none` falls back to the phone dialer after the driver arrives.

1. Open an Exotel account and finish the company KYC; buy one **ExoPhone** (virtual number) in it.
2. In the Exotel dashboard copy the **Account SID**, **API key** and **API token**, and note the API subdomain shown there (`api.exotel.com` or `api.in.exotel.com`).
3. In `backend/.env` set `CALL_PROVIDER=exotel`, `EXOTEL_SID`, `EXOTEL_API_KEY`, `EXOTEL_API_TOKEN`, `EXOTEL_SUBDOMAIN`, `EXOTEL_CALLER_ID=<the ExoPhone in E.164, e.g. +911140001234>`.
4. Set `CALL_STATUS_CALLBACK_URL=https://<your api host>/v1/webhooks/calls/exotel` and a random `CALL_STATUS_SECRET`; Exotel posts each call's outcome there so the admin panel can show talk time.
5. Restart the API. Book a test ride, accept it, tap **Call** in either app: your phone rings from the ExoPhone and connects you to the other party once you answer.

Tuning: `CALL_MAX_SECONDS` (default 600) caps a call; `CALL_MIN_INTERVAL_SECONDS` (default 15) throttles repeat taps.
