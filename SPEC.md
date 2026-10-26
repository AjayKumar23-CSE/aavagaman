---
title: "Delhi NCR Ride-Hailing Platform — Production Build Specification"
subtitle: "Technical spec for building the rider app, driver app, admin panel and backend with an AI coding agent (Claude Code)"
date: "Version 1.0 — 27 September 2026"
---

# 0. How to use this document with Claude Code

This document is written so that an AI coding agent (Claude Code running Claude Fable 5.1 or Claude Opus 5) can build the entire system from it, phase by phase. Follow these rules for good results.

**Working method**

1. Put this PDF (or its Markdown source) in the repository root as `SPEC.md` and add a `CLAUDE.md` that says: *"Read SPEC.md before any task. Follow its stack, schema, API contracts and acceptance criteria exactly. Do not add features that are marked Later."*
2. Build in the phase order of Section 20. Give the agent one phase at a time, and ask it to finish with the phase's acceptance checklist passing.
3. After each phase, run the tests, run the app on a real Android phone, and commit. Do not start the next phase with failing tests.
4. When the agent proposes a different library or design, ask it to justify against this spec; accept only if the change is recorded in `docs/DECISIONS.md`.
5. Keep secrets out of the repo. The agent reads `.env.example`; you keep `.env`.

**Prompt template per phase**

> You are building Phase N of the ride-hailing platform described in SPEC.md. Scope: <copy the phase's scope>. Constraints: use only the stack in Section 2, the schema in Section 5, the API contract in Section 7 and the events in Section 8. Write unit tests for the fare engine and matching logic. When done, list how each acceptance item in Section 20 Phase N is satisfied and how I can verify it manually.

**Non-goals for the agent**: no pooling, scheduled rides, surge pricing, multiple cities, promo codes, wallets, in-app chat, iOS build (until Phase 7), or any feature marked Later in Section 1.

---

# 1. Product summary and scope

**Product**: a small-scale cab-booking platform for Delhi NCR (Delhi, Gurugram, Faridabad, Noida, Greater Noida, Ghaziabad). Three clients share one backend:

- **Rider app** (Flutter, Android first): book, track, pay, rate.
- **Driver app** (Flutter, Android): go online, accept requests, run trips, see earnings.
- **Admin panel** (React web): approve drivers, live map, rides, fares, reports, settlements.

**Pilot targets**: 20–30 drivers, ~60 rides/day, cash-first, single vehicle type (sedan), English UI.

## 1.1 Feature scope

| Area | MVP (build) | Later (do not build) |
|---|---|---|
| Auth | Phone OTP for riders and drivers; email+password for admin | Social login |
| Booking | Pickup/drop with Places autocomplete; fare estimate; single vehicle type | Scheduled rides, multiple vehicle types, pooling |
| Matching | Nearest idle driver, 20 s offer timeout, up to 3 offers / 2 min | Batch matching, ML ETA |
| Trip | Accepted → Arrived → OTP → Started → Completed; GPS track | Multi-stop trips |
| Tracking | Live driver location to rider and admin via WebSocket | — |
| Fare | base + per-km + per-min, min fare, night multiplier, 125% cap | Surge pricing |
| Payments | Cash; Razorpay UPI/card; weekly settlement report | Wallet, promo codes, auto payouts |
| Safety | 4-digit trip OTP, share trip link, SOS to 112 + admin alert | Masked calling, in-app chat |
| Driver onboarding | Document upload and admin approval; expiry tracking | Automated KYC |
| Admin | Live map, rides, drivers, riders, fare config, service area, reports, settlements | Role-based multi-admin |
| Geofence | One or more active polygons (Delhi NCR) | — |
| Platform | Android (Play Store) | iOS (Phase 7) |
| Language | English (strings externalised) | Hindi |

---

# 2. Technology stack (final decisions)

| Layer | Decision | Version / notes |
|---|---|---|
| Mobile apps | Flutter | 3.x stable; Dart 3; Riverpod for state; go_router; dio; socket_io_client; google_maps_flutter; geolocator; flutter_background_service (driver); firebase_messaging; firebase_crashlytics |
| Admin panel | React + TypeScript + Vite | Tailwind CSS; TanStack Query; react-router; Leaflet or Google Maps JS for live map; Recharts |
| Backend | Node.js 22 + NestJS 10 + TypeScript | REST + Socket.io gateway in one process; class-validator DTOs; Swagger at `/docs` |
| ORM / DB | Prisma or TypeORM with PostgreSQL 16 + PostGIS 3 | Prisma preferred; raw SQL for PostGIS queries |
| Cache / geo | Redis 7 | GEO commands for driver positions; BullMQ for jobs |
| Routing | OSRM (self-hosted, Docker) with Delhi NCR OpenStreetMap extract | Google Directions API as fallback when OSRM errors |
| Maps in apps | Google Maps Platform | Maps SDK (free), Places Autocomplete (session tokens, NCR bounds) |
| Push | Firebase Cloud Messaging | Blaze (pay-as-you-go) plan |
| SMS OTP | MSG91 | DLT-registered template; fallback provider interface |
| Payments | Razorpay Standard Checkout + webhooks | Orders API; signature verification |
| Object storage | Cloudflare R2 (S3-compatible) | Driver documents, photos, DB dumps |
| Hosting | One VPS (Hetzner CX22 / DigitalOcean 2 GB / AWS t4g.small) | Docker Compose; Caddy for HTTPS |
| DNS / CDN | Cloudflare | Admin panel on Cloudflare Pages |
| Monitoring | Sentry (backend + apps), UptimeRobot | Structured JSON logs via pino |
| CI/CD | GitHub Actions | Lint, test, build APKs, deploy on push to `main` |

**Rules**: no other databases; no Firebase Firestore/Realtime DB; no serverless functions; no Kubernetes. All config via environment variables. All timestamps stored in UTC, displayed in IST.

---

# 3. Repository structure (monorepo)

```
ride-platform/
  CLAUDE.md
  SPEC.md
  README.md
  docs/
    DECISIONS.md          # architecture decision log
    RUNBOOK.md            # ops procedures
    ADMIN_GUIDE.md        # with screenshots
  backend/                # NestJS
    src/
      main.ts
      app.module.ts
      common/             # guards, filters, interceptors, utils
      config/             # env schema (zod), config module
      modules/
        auth/             # OTP, JWT, admin login
        users/
        drivers/          # profile, documents, approval
        vehicles/
        location/         # ingest GPS, Redis GEO, nearby query
        rides/            # state machine, request, lifecycle
        matching/         # offer loop, timeouts (BullMQ)
        fare/             # estimate + final fare
        geofence/         # service areas
        routing/          # OSRM client + Google fallback
        payments/         # Razorpay orders, webhooks, cash
        settlements/
        notifications/    # FCM + SMS
        admin/            # admin-only endpoints, reports
        realtime/         # Socket.io gateway
      prisma/
        schema.prisma
        migrations/
    test/                 # unit + e2e (Jest)
    Dockerfile
  apps/
    rider/                # Flutter
    driver/               # Flutter
    shared/               # Flutter package: api client, models, theme, widgets
  admin/                  # React + Vite
  infra/
    docker-compose.yml
    docker-compose.prod.yml
    Caddyfile
    osrm/                 # download + build scripts for NCR extract
    backup/               # pg_dump to R2 script + cron
  .github/workflows/
    backend.yml
    apps.yml
    admin.yml
```

---

# 4. Configuration and environment variables

`backend/.env.example` (the agent must create this; values are placeholders):

```
NODE_ENV=production
PORT=3000
API_BASE_URL=https://api.example.com
ADMIN_ORIGIN=https://admin.example.com

DATABASE_URL=postgresql://ride:password@postgres:5432/ride
REDIS_URL=redis://redis:6379

JWT_ACCESS_SECRET=change-me
JWT_REFRESH_SECRET=change-me
JWT_ACCESS_TTL=15m
JWT_REFRESH_TTL=90d

OTP_TTL_SECONDS=300
OTP_MAX_ATTEMPTS=3
OTP_DEV_BYPASS_CODE=            # set only in dev, e.g. 123456

MSG91_AUTH_KEY=
MSG91_TEMPLATE_ID=
MSG91_SENDER_ID=

FCM_SERVICE_ACCOUNT_JSON_BASE64=

GOOGLE_MAPS_SERVER_KEY=         # Directions fallback only
OSRM_BASE_URL=http://osrm:5000

RAZORPAY_KEY_ID=
RAZORPAY_KEY_SECRET=
RAZORPAY_WEBHOOK_SECRET=

S3_ENDPOINT=https://<account>.r2.cloudflarestorage.com
S3_BUCKET=ride-docs
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
S3_PUBLIC_BASE_URL=             # leave empty; serve via signed URLs

SENTRY_DSN=
LOG_LEVEL=info

# Business defaults (overridden by fare_config rows)
DEFAULT_SEARCH_RADIUS_KM=3
DEFAULT_SEARCH_RADIUS_RETRY_KM=5
OFFER_TIMEOUT_SECONDS=20
MAX_OFFERS_PER_RIDE=3
MATCHING_DEADLINE_SECONDS=120
DRIVER_HEARTBEAT_TTL_SECONDS=15
```

Validate all variables at boot with a zod schema; fail fast with a clear message if any required variable is missing.

---

# 5. Database schema (PostgreSQL + PostGIS)

Use Prisma for ordinary columns; PostGIS columns are declared as `Unsupported("geography(Point,4326)")` / `Unsupported("geography(Polygon,4326)")` and queried with raw SQL. All ids are UUID v4. All tables have `created_at`, `updated_at`.

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE user_role AS ENUM ('rider','driver','admin');
CREATE TYPE user_status AS ENUM ('active','blocked');
CREATE TYPE verification_status AS ENUM ('pending','approved','rejected','suspended');
CREATE TYPE ride_status AS ENUM ('REQUESTED','ACCEPTED','ARRIVED','STARTED','COMPLETED','PAID','CANCELLED','NO_DRIVER');
CREATE TYPE cancel_actor AS ENUM ('rider','driver','admin','system');
CREATE TYPE offer_response AS ENUM ('accepted','rejected','timeout');
CREATE TYPE payment_method AS ENUM ('cash','upi','card','wallet');
CREATE TYPE payment_status AS ENUM ('pending','paid','failed','refunded');
CREATE TYPE doc_type AS ENUM ('driving_licence','rc','insurance','permit','id_proof','selfie','fitness');

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone VARCHAR(15) UNIQUE NOT NULL,           -- E.164, e.g. +9198xxxxxxxx
  name VARCHAR(80),
  email VARCHAR(120),
  role user_role NOT NULL,
  status user_status NOT NULL DEFAULT 'active',
  password_hash TEXT,                          -- admin only (argon2)
  fcm_token TEXT,
  rating_avg NUMERIC(3,2) DEFAULT 5.00,
  rating_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE drivers (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  licence_no VARCHAR(40),
  licence_expiry DATE,
  id_last4 VARCHAR(4),
  selfie_key TEXT,
  verification_status verification_status NOT NULL DEFAULT 'pending',
  reviewer_note TEXT,
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  cancel_count_today INT DEFAULT 0,
  cancel_count_reset_at DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(user_id),
  reg_number VARCHAR(15) NOT NULL,
  make VARCHAR(40), model VARCHAR(40), colour VARCHAR(30),
  vehicle_type VARCHAR(20) NOT NULL DEFAULT 'sedan',
  fuel_type VARCHAR(20),                        -- petrol/diesel/cng/ev (EV reporting)
  insurance_expiry DATE, permit_expiry DATE, fitness_expiry DATE,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX one_active_vehicle_per_driver ON vehicles(driver_id) WHERE active;

CREATE TABLE driver_documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(user_id),
  doc_type doc_type NOT NULL,
  file_key TEXT NOT NULL,                       -- R2 object key
  status verification_status NOT NULL DEFAULT 'pending',
  reviewer_note TEXT,
  expiry DATE,
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE fare_config (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  vehicle_type VARCHAR(20) NOT NULL DEFAULT 'sedan',
  base_fare NUMERIC(8,2) NOT NULL,
  per_km NUMERIC(8,2) NOT NULL,
  per_min NUMERIC(8,2) NOT NULL,
  min_fare NUMERIC(8,2) NOT NULL,
  cancellation_fee NUMERIC(8,2) NOT NULL DEFAULT 30,
  night_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00,  -- applied 23:00–05:00 IST
  night_enabled BOOLEAN NOT NULL DEFAULT false,
  commission_pct NUMERIC(5,2) NOT NULL DEFAULT 15.00,
  gst_pct NUMERIC(5,2) NOT NULL DEFAULT 5.00,
  effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES users(id)
);

CREATE TABLE service_areas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(60) NOT NULL,
  polygon geography(Polygon,4326) NOT NULL,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX service_areas_gix ON service_areas USING GIST (polygon);

CREATE TABLE rides (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rider_id UUID NOT NULL REFERENCES users(id),
  driver_id UUID REFERENCES drivers(user_id),
  vehicle_id UUID REFERENCES vehicles(id),
  status ride_status NOT NULL DEFAULT 'REQUESTED',
  vehicle_type VARCHAR(20) NOT NULL DEFAULT 'sedan',
  pickup_point geography(Point,4326) NOT NULL,
  pickup_address TEXT NOT NULL,
  drop_point geography(Point,4326) NOT NULL,
  drop_address TEXT NOT NULL,
  est_distance_m INT, est_duration_s INT,
  est_fare_min NUMERIC(8,2), est_fare_max NUMERIC(8,2),
  actual_distance_m INT, actual_duration_s INT,
  final_fare NUMERIC(8,2),
  fare_config_id UUID REFERENCES fare_config(id),
  cancellation_fee NUMERIC(8,2) DEFAULT 0,
  cancelled_by cancel_actor, cancel_reason TEXT,
  trip_otp CHAR(4) NOT NULL,
  share_token VARCHAR(32) UNIQUE,
  requested_at TIMESTAMPTZ DEFAULT now(),
  accepted_at TIMESTAMPTZ, arrived_at TIMESTAMPTZ, started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ, paid_at TIMESTAMPTZ, cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX rides_status_time ON rides(status, requested_at DESC);
CREATE INDEX rides_rider ON rides(rider_id, requested_at DESC);
CREATE INDEX rides_driver ON rides(driver_id, requested_at DESC);
CREATE INDEX rides_pickup_gix ON rides USING GIST (pickup_point);
-- A driver can have at most one ride in an active state
CREATE UNIQUE INDEX one_active_ride_per_driver ON rides(driver_id)
  WHERE status IN ('ACCEPTED','ARRIVED','STARTED');

CREATE TABLE ride_offers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ride_id UUID NOT NULL REFERENCES rides(id),
  driver_id UUID NOT NULL REFERENCES drivers(user_id),
  distance_to_pickup_m INT,
  offered_at TIMESTAMPTZ DEFAULT now(),
  responded_at TIMESTAMPTZ,
  response offer_response
);
CREATE INDEX ride_offers_ride ON ride_offers(ride_id);

CREATE TABLE ride_events (
  id BIGSERIAL PRIMARY KEY,
  ride_id UUID NOT NULL REFERENCES rides(id),
  from_status ride_status, to_status ride_status NOT NULL,
  actor cancel_actor NOT NULL, actor_id UUID,
  meta JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ride_events_ride ON ride_events(ride_id, created_at);

CREATE TABLE ride_tracks (
  ride_id UUID NOT NULL REFERENCES rides(id),
  recorded_at TIMESTAMPTZ NOT NULL,
  point geography(Point,4326) NOT NULL,
  speed_mps REAL, accuracy_m REAL,
  PRIMARY KEY (ride_id, recorded_at)
);

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ride_id UUID UNIQUE NOT NULL REFERENCES rides(id),
  method payment_method NOT NULL,
  amount NUMERIC(8,2) NOT NULL,
  status payment_status NOT NULL DEFAULT 'pending',
  gateway_order_id TEXT, gateway_payment_id TEXT, gateway_signature TEXT,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE ratings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ride_id UUID NOT NULL REFERENCES rides(id),
  from_user_id UUID NOT NULL REFERENCES users(id),
  to_user_id UUID NOT NULL REFERENCES users(id),
  stars SMALLINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (ride_id, from_user_id)
);

CREATE TABLE driver_settlements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(user_id),
  period_start DATE NOT NULL, period_end DATE NOT NULL,
  rides_count INT, gross_fares NUMERIC(10,2), commission NUMERIC(10,2),
  cash_collected NUMERIC(10,2), online_collected NUMERIC(10,2),
  amount_payable NUMERIC(10,2),          -- positive: platform pays driver; negative: driver pays platform
  settled_at TIMESTAMPTZ, reference TEXT, settled_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (driver_id, period_start)
);

CREATE TABLE sos_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ride_id UUID REFERENCES rides(id),
  user_id UUID NOT NULL REFERENCES users(id),
  point geography(Point,4326),
  acknowledged_by UUID REFERENCES users(id), acknowledged_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  actor_id UUID, action VARCHAR(60) NOT NULL, entity VARCHAR(40), entity_id UUID,
  before JSONB, after JSONB, created_at TIMESTAMPTZ DEFAULT now()
);
```

**Retention job (daily, 03:00 IST)**: delete `ride_tracks` older than 30 days; delete expired OTPs (Redis handles TTL); archive nothing else.

**Seed data**: one admin user, one `fare_config` row (base 50, per_km 12, per_min 1.5, min 80, cancellation 30, commission 15), one `service_areas` row for Delhi NCR (GeoJSON in `infra/seed/ncr.geojson`).

---

# 6. Redis data structures

| Key | Type | Content | TTL |
|---|---|---|---|
| `drivers:geo` | GEO set | member = driver_id, position = last lat/lng | none (removed on offline / heartbeat expiry) |
| `driver:{id}:hb` | string | last heartbeat ISO time | 15 s, refreshed by every location update |
| `driver:{id}:state` | string | `idle` / `offered` / `on_trip` / `offline` | none |
| `driver:{id}:loc` | hash | lat, lng, heading, speed, ts | 60 s |
| `ride:{id}:offer` | hash | driver_id, offered_at, expires_at | 25 s |
| `ride:{id}:offered_set` | set | driver_ids already offered this ride | 10 min |
| `otp:{phone}` | hash | code_hash, attempts | 300 s |
| `otp:rl:{phone}` | counter | OTP send count | 1 h (max 5) |
| `ws:user:{id}` | set | socket ids for the user | none |

A BullMQ **heartbeat sweeper** runs every 10 s: any driver in `drivers:geo` whose `hb` key has expired is removed from the GEO set and marked `offline`; if that driver had an `offered` state, the offer is treated as `timeout`.

---

# 7. REST API contract

Base URL `/v1`. JSON only. Auth: `Authorization: Bearer <access_jwt>`. Errors use `{ "error": { "code": "RIDE_NOT_CANCELLABLE", "message": "..." } }` with proper HTTP status. All list endpoints support `?page=&limit=` (max 100). Swagger generated at `/docs` (disabled in production unless `ENABLE_DOCS=true`).

## 7.1 Auth

| Method | Path | Body / params | Response | Notes |
|---|---|---|---|---|
| POST | `/auth/otp/send` | `{phone, role: "rider" or "driver"}` | `{sent: true, ttl: 300}` | Rate limit 5/h per phone; 3/min per IP |
| POST | `/auth/otp/verify` | `{phone, code, role, device: {platform, fcm_token, app_version}}` | `{access_token, refresh_token, user}` | Creates user if new rider; driver must be pre-registered or goes to pending |
| POST | `/auth/refresh` | `{refresh_token}` | `{access_token, refresh_token}` | Rotating refresh tokens; revoke on reuse |
| POST | `/auth/logout` | — | `204` | Clears fcm_token |
| POST | `/auth/admin/login` | `{email, password}` | `{access_token, refresh_token}` | argon2; lockout after 10 failures |

## 7.2 Rider

| Method | Path | Body / params | Response |
|---|---|---|---|
| GET | `/me` | — | user profile |
| PATCH | `/me` | `{name?, email?}` | user |
| POST | `/me/fcm-token` | `{token}` | 204 |
| POST | `/fare/estimate` | `{pickup:{lat,lng,address}, drop:{lat,lng,address}}` | `{distance_m, duration_s, fare_min, fare_max, currency:"INR", in_service_area:{pickup:true, drop:true}, fare_config_id}` |
| GET | `/drivers/nearby?lat=&lng=` | — | `[{driver_id, lat, lng, heading}]` (max 10, anonymised, for the "cars around you" map) |
| POST | `/rides` | `{pickup, drop, fare_config_id, payment_method:"cash" or "online"}` | ride (status REQUESTED) — 409 if rider already has an active ride; 422 if pickup outside area |
| GET | `/rides/active` | — | active ride or 404 |
| GET | `/rides/:id` | — | ride with driver public info and vehicle |
| POST | `/rides/:id/cancel` | `{reason?}` | ride (CANCELLED) with fee applied |
| GET | `/rides` | `?page` | ride history |
| GET | `/rides/:id/receipt` | — | fare breakdown |
| POST | `/rides/:id/rating` | `{stars, comment?}` | 201 |
| POST | `/rides/:id/sos` | `{lat,lng}` | 201 |
| POST | `/rides/:id/payment/order` | — | `{razorpay_order_id, amount, key_id}` |
| POST | `/rides/:id/payment/verify` | `{razorpay_payment_id, razorpay_order_id, razorpay_signature}` | payment (paid) |
| GET | `/share/:token` | public | `{status, driver_name, vehicle, current_location, eta}` |

## 7.3 Driver

| Method | Path | Body / params | Response |
|---|---|---|---|
| POST | `/driver/register` | `{name, licence_no, licence_expiry, vehicle:{reg_number, make, model, colour, fuel_type}}` | driver (pending) |
| POST | `/driver/documents/presign` | `{doc_type, content_type}` | `{upload_url, file_key}` (R2 presigned PUT, 10 min) |
| POST | `/driver/documents` | `{doc_type, file_key, expiry?}` | document |
| GET | `/driver/me` | — | driver profile + verification status + vehicle + documents |
| POST | `/driver/online` | `{lat,lng}` | 204 — 403 unless approved and all mandatory docs approved and not expired |
| POST | `/driver/offline` | — | 204 — 409 if on_trip |
| POST | `/driver/location` | `{lat,lng,heading,speed,accuracy,ts}` | 204 (also accepted over WebSocket; REST is the fallback) |
| GET | `/driver/rides/active` | — | active ride with rider name, phone (masked to last 4 until ARRIVED), pickup, drop |
| POST | `/driver/rides/:id/accept` | — | ride (ACCEPTED) — 409 if already taken/expired |
| POST | `/driver/rides/:id/reject` | — | 204 |
| POST | `/driver/rides/:id/arrived` | `{lat,lng}` | ride — 422 if more than 300 m from pickup (admin-configurable) |
| POST | `/driver/rides/:id/start` | `{otp, lat, lng}` | ride (STARTED) — 401 on wrong OTP, 3 attempts |
| POST | `/driver/rides/:id/complete` | `{lat,lng}` | ride (COMPLETED) with final_fare |
| POST | `/driver/rides/:id/cancel` | `{reason}` | ride (CANCELLED) |
| POST | `/driver/rides/:id/cash-collected` | — | payment (paid, cash) |
| GET | `/driver/earnings?period=today or week` | — | `{rides, gross, commission, net, cash_collected, online}` |
| GET | `/driver/rides` | `?page` | history |
| POST | `/driver/rides/:id/rating` | `{stars}` | 201 |

## 7.4 Admin (role = admin)

| Method | Path | Purpose |
|---|---|---|
| GET | `/admin/dashboard` | today's counts: rides by status, online drivers, revenue, cancellations |
| GET | `/admin/drivers?status=&q=` | list with verification status |
| GET | `/admin/drivers/:id` | full profile, documents (signed view URLs), vehicle, stats |
| POST | `/admin/drivers/:id/approve` / `reject` / `suspend` / `reinstate` | body `{note?}` |
| POST | `/admin/drivers/:id/documents/:docId/approve` / `reject` | body `{note?}` |
| PATCH | `/admin/drivers/:id/vehicle` | edit vehicle |
| GET | `/admin/riders?q=` / `POST /admin/riders/:id/block` / `unblock` | |
| GET | `/admin/rides?status=&from=&to=&driver_id=&rider_id=` | list |
| GET | `/admin/rides/:id` | ride + events + track (GeoJSON) + offers + payment |
| POST | `/admin/rides/:id/cancel` | `{reason}` |
| POST | `/admin/rides/:id/reassign` | `{driver_id}` (only ACCEPTED/ARRIVED) |
| POST | `/admin/rides/:id/adjust-fare` | `{final_fare, reason}` (logged) |
| POST | `/admin/rides/:id/mark-cash` | |
| GET / POST | `/admin/fare-config` | list history / create new effective config |
| GET / POST / PATCH | `/admin/service-areas` | GeoJSON polygon in, out |
| GET | `/admin/live` | online drivers + active rides snapshot (WebSocket `admin:live` streams updates) |
| GET | `/admin/reports/daily?from=&to=` | rides, revenue, commission, cash vs online, cancellations; `?format=csv` |
| GET | `/admin/settlements?week=` / `POST /admin/settlements/generate` / `POST /admin/settlements/:id/settle` | weekly settlement flow |
| GET | `/admin/sos` / `POST /admin/sos/:id/ack` | |
| GET | `/admin/audit?entity=&entity_id=` | |

## 7.5 Webhooks and system

| Method | Path | Notes |
|---|---|---|
| POST | `/webhooks/razorpay` | Verify `X-Razorpay-Signature` with webhook secret; handle `payment.captured`, `payment.failed`; idempotent on `gateway_payment_id` |
| GET | `/health` | `{status:"ok", db:true, redis:true, osrm:true}` |
| GET | `/metrics` | Prometheus text (basic counters), protected by token |

---

# 8. WebSocket events (Socket.io, namespace `/rt`)

Handshake: `auth: { token: <access_jwt> }`. Server joins socket to rooms `user:{id}` and, for admins, `admin`. Reconnection is expected; on connect the server re-sends the current active ride (if any).

**Client → server**

| Event | Sender | Payload |
|---|---|---|
| `driver:location` | driver | `{lat,lng,heading,speed,accuracy,ts}` every 4 s while online; every 2 s while ACCEPTED/STARTED |
| `driver:offer:accept` | driver | `{ride_id}` (same as REST accept) |
| `driver:offer:reject` | driver | `{ride_id}` |
| `rider:subscribe` | rider | `{ride_id}` |
| `admin:subscribe` | admin | `{}` |

**Server → client**

| Event | To | Payload |
|---|---|---|
| `ride:offer` | driver | `{ride_id, pickup:{lat,lng,address}, drop_address, distance_to_pickup_m, est_fare_min, est_fare_max, expires_at}` |
| `ride:offer:expired` | driver | `{ride_id}` |
| `ride:status` | rider, driver, admin | `{ride_id, status, driver?:{id,name,rating,phone_masked,vehicle:{reg_number,make,model,colour}}, final_fare?, cancellation_fee?, cancelled_by?}` |
| `driver:position` | rider (own ride), admin | `{driver_id, lat, lng, heading, eta_s?}` |
| `ride:no_driver` | rider | `{ride_id}` |
| `payment:status` | rider, driver | `{ride_id, status, method}` |
| `admin:live` | admin | batched every 2 s: `{drivers:[...], rides:[...]}` |
| `sos:alert` | admin | `{ride_id, user_id, lat, lng, at}` |

Every state change is emitted via `ride:status` **and** sent as an FCM push (Section 14) so a backgrounded app still learns about it.

---

# 9. Core algorithms

## 9.1 Geofence

`isInsideServiceArea(lat, lng)`:
```sql
SELECT EXISTS (
  SELECT 1 FROM service_areas
  WHERE active AND ST_Covers(polygon, ST_SetSRID(ST_MakePoint($lng,$lat),4326)::geography)
);
```
Pickup outside → reject request (422 `OUTSIDE_SERVICE_AREA`). Drop outside → allowed; response flags `in_service_area.drop=false` and the app shows a notice.

## 9.2 Routing

`RoutingService.route(from, to)` calls OSRM `/route/v1/driving/{lng},{lat};{lng},{lat}?overview=false` and returns `{distance_m, duration_s}`. On error or timeout (2 s), call Google Directions with `departure_time=now`; if both fail, return 503 `ROUTING_UNAVAILABLE`. Cache results in Redis for 60 s keyed on rounded coordinates (4 decimals).

## 9.3 Fare engine (pure function, unit-tested)

```
estimate(distance_m, duration_s, cfg, now):
  km  = distance_m / 1000
  min = duration_s / 60
  raw = cfg.base_fare + cfg.per_km * km + cfg.per_min * min
  if cfg.night_enabled and isNight(now, IST 23:00–05:00): raw *= cfg.night_multiplier
  fare = max(cfg.min_fare, raw)
  return { fare_min: round(fare * 0.95), fare_max: round(fare * 1.10), fare }

finalFare(actual_distance_m, actual_duration_s, cfg, estimate, drop_changed, started_at):
  f = estimate-like calculation with actual values and started_at for night check
  cap = drop_changed ? Infinity : estimate.fare * 1.25
  fare = min(max(cfg.min_fare, f), cap)
  return round(fare)      # nearest rupee
```

GST: fares are GST-inclusive; receipts show `gst = fare - fare / (1 + gst_pct/100)`. Commission is computed on the fare excluding GST.

**Actual distance**: sum of haversine distances between consecutive accepted `ride_tracks` points (drop points with accuracy > 50 m or implied speed > 40 m/s); if fewer than 3 points exist, fall back to OSRM distance between `started` and `completed` coordinates.

## 9.4 Matching (BullMQ job `match-ride`)

```
onRideRequested(ride):
  enqueue match-ride {ride_id, attempt:1, radius: 3 km, deadline: now + 120 s}

match-ride job:
  if ride.status != REQUESTED: return
  if now > deadline: setStatus(NO_DRIVER); emit ride:no_driver; return
  candidates = GEOSEARCH drivers:geo FROMLONLAT pickup BYRADIUS radius km ASC COUNT 10
  candidates = filter: state == idle, not in ride:{id}:offered_set, vehicle_type matches
  if empty:
     if attempt == 1: re-enqueue with radius 5 km, attempt 2, delay 3 s; return
     re-enqueue with same params, delay 5 s; return
  driver = candidates[0]
  SET driver:{id}:state offered ; HSET ride:{id}:offer ; SADD offered_set
  INSERT ride_offers ; emit ride:offer to driver (WS + FCM high-priority)
  enqueue offer-timeout {ride_id, driver_id} delay OFFER_TIMEOUT_SECONDS

offer-timeout job:
  if ride:{id}:offer.driver_id != driver_id or response already recorded: return
  mark offer timeout ; state idle ; emit ride:offer:expired
  if count(offers for ride) >= MAX_OFFERS_PER_RIDE: setStatus(NO_DRIVER); return
  enqueue match-ride (same deadline, attempt+1)

accept(driver, ride_id):  -- in one DB transaction
  SELECT ... FROM rides WHERE id=$1 FOR UPDATE
  if status != REQUESTED or ride:{id}:offer.driver_id != driver: 409 OFFER_NOT_VALID
  UPDATE rides SET status=ACCEPTED, driver_id, vehicle_id, accepted_at
  INSERT ride_events ; state on_trip ; DEL ride:{id}:offer
  emit ride:status to rider/driver/admin ; push to rider
```

Rider cancel during REQUESTED cancels pending jobs (job ids are `match:{ride_id}` and `offer:{ride_id}:{driver_id}` so they can be removed).

## 9.5 Cancellation rules

| Situation | Fee | Effect |
|---|---|---|
| Rider cancels in REQUESTED | 0 | — |
| Rider cancels within 120 s of `accepted_at` | 0 | driver → idle |
| Rider cancels later, or after ARRIVED | `cfg.cancellation_fee` | stored on ride; added as a line item to the rider's next completed ride (`rides.cancellation_fee` on that ride, from a `pending_fees` lookup); driver → idle |
| Rider no-show: driver may cancel 300 s after `arrived_at` | `cfg.cancellation_fee` | same as above; not counted against driver |
| Driver cancels after ACCEPTED (before ARRIVED + 300 s) | 0 to rider | `drivers.cancel_count_today++`; at 3 → `verification_status = suspended` and admin notified; ride returns to REQUESTED and matching restarts with that driver excluded |
| Admin cancels | 0 | reason mandatory, logged |

## 9.6 Trip OTP

4 digits, generated at ride creation, shown to the rider once ACCEPTED. `start` compares in constant time; 3 wrong attempts → ride flagged, admin notified, driver may still cancel. OTP is never sent by SMS unless the rider's app is offline for more than 60 s after ARRIVED (fallback job).

## 9.7 ETA to pickup

Recomputed every 15 s while ACCEPTED using OSRM from driver position to pickup; included in `driver:position` as `eta_s`.

---

# 10. Ride state machine (enforced server-side)

| From | Event | To | Allowed actor |
|---|---|---|---|
| — | request | REQUESTED | rider |
| REQUESTED | accept | ACCEPTED | driver (offered only) |
| REQUESTED | no driver | NO_DRIVER | system |
| REQUESTED | cancel | CANCELLED | rider, admin |
| ACCEPTED | arrived | ARRIVED | driver |
| ACCEPTED | cancel | CANCELLED (or back to REQUESTED on driver cancel) | rider, driver, admin |
| ACCEPTED | reassign | ACCEPTED (new driver) | admin |
| ARRIVED | start (OTP ok) | STARTED | driver |
| ARRIVED | cancel | CANCELLED | rider (fee), driver (after 300 s, fee), admin |
| STARTED | complete | COMPLETED | driver |
| STARTED | cancel | CANCELLED | admin only (fare adjusted manually) |
| COMPLETED | cash collected / online captured | PAID | driver / webhook / admin |

Any other transition → 409 `INVALID_TRANSITION`. Every transition writes `ride_events`, emits `ride:status`, and sends the matching push.

---

# 11. Rider app (Flutter)

**Screens**: Splash → Phone → OTP → Name (first time) → Home (map) → Set drop (search) → Confirm (fare, payment method, Book) → Finding driver → Driver assigned / En route → Trip in progress → Fare & payment → Rate → Home. Drawer: Ride history, Ride detail/receipt, Profile, Help/Support (phone + email), Privacy policy, Delete account.

**Behaviours**

- Home map centred on GPS location; if permission denied, centre on Connaught Place (28.6315, 77.2167) and show a prompt.
- Nearby drivers refreshed every 10 s via `GET /drivers/nearby`; shown as car icons (no identity).
- Places Autocomplete: `locationRestriction` = NCR bounding box (approx. SW 28.20,76.80 to NE 28.95,77.70), `components=country:in`, session tokens, 400 ms debounce, minimum 3 characters.
- Confirm screen shows fare range, payment method selector (Cash default / Pay online), out-of-area drop notice.
- Finding screen: 2-minute countdown, Cancel button, handles `ride:no_driver`.
- Assigned screen: driver card (photo, name, rating, vehicle, plate), live car marker, ETA, trip OTP shown large, Call, Share trip (generates `share_token` URL), Cancel (shows fee warning after 2 min), SOS (confirm → dial 112 → POST sos).
- In-progress: route line, drop marker, SOS, Share.
- End: fare breakdown; if online, launches Razorpay Checkout; on success POST verify; on failure allow retry or switch to cash (driver confirms).
- Rating screen; skip allowed.
- App resumes correctly: on launch always call `GET /rides/active` and re-subscribe.
- Localisation: all strings in ARB files; English only for now.

**Permissions**: location (while in use), notifications, phone (dialer intent only). No background location on the rider app.

---

# 12. Driver app (Flutter)

**Screens**: Splash → Phone → OTP → Registration (profile, vehicle) → Documents upload (each doc: camera/gallery, compressed to ≤ 800 KB JPEG, presigned PUT) → Pending approval (status + reasons) → Home (Online/Offline switch, today's earnings) → Offer popup (full-screen, sound, vibration, 20 s ring) → Navigate to pickup → Arrived → OTP entry → Trip → Complete → Collect payment → Home. Drawer: Earnings, Trip history, Profile/Vehicle/Documents, Help, Privacy.

**Background location (critical)**

- Use `flutter_background_service` with a foreground service and persistent notification "You are online".
- Request `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` (Android 10+), `FOREGROUND_SERVICE_LOCATION` (Android 14+), `POST_NOTIFICATIONS`.
- Send `driver:location` every 4 s while idle, every 2 s during an active ride; batch and send via REST if the socket is disconnected; drop points with accuracy > 100 m.
- Show a one-time guide to disable battery optimisation for the app (deep-link to settings), with brand-specific notes for Xiaomi/Vivo/Oppo/Realme/Samsung.
- If the socket drops for > 15 s the server marks the driver offline; the app must show "Reconnecting…" and re-send `POST /driver/online` on reconnect if the switch is still on.

**Offer popup**: shows pickup address, distance to pickup, fare range, countdown ring; Accept / Reject; plays a loud repeating tone and vibrates; uses a high-priority FCM data message to wake the app if the socket is asleep; a full-screen intent notification on Android when locked.

**Navigation**: `Navigate` opens `google.navigation:q=lat,lng` intent (falls back to a maps URL).

**Trip screen**: big status button (Arrived → Start Trip → End Trip), rider name and masked phone (full phone after ARRIVED), Call, Cancel with reason picker, SOS.

**Payment screen**: final fare; "Cash collected" button (confirm dialog), or "Waiting for online payment" with spinner that resolves on `payment:status`.

**Earnings**: today/week cards; list of trips with fare, commission, net.

---

# 13. Admin panel (React)

**Pages**: Login · Dashboard · Live map · Rides (list, detail with timeline, map track, offers, payment, actions) · Drivers (list, detail with document viewer and approve/reject per document, vehicle edit, suspend) · Riders · Fare config (history + new version form with preview calculator) · Service areas (map editor: draw/edit polygon, import GeoJSON) · Reports (date range, charts, CSV) · Settlements (generate week, per-driver statement, mark settled) · SOS alerts · Audit log · Settings (admin password).

**Live map**: subscribes to `admin:live`; drivers coloured by state (idle green, offered amber, on_trip blue); active rides as lines pickup→drop; click for details. Auto-refresh without page reload.

**Non-functional**: responsive down to 1024 px; all tables paginated and filterable; every destructive action has a confirm dialog with reason; times displayed in IST.

---

# 14. Notification matrix

| Event | Rider push | Driver push | SMS |
|---|---|---|---|
| OTP requested | — | — | Login OTP |
| Ride offer | — | High-priority data message "New ride request" (wakes app) | — |
| ACCEPTED | "Driver <name> is on the way (<plate>)" | — | — |
| Driver within 300 m | "Your driver is nearby" | — | — |
| ARRIVED | "Your driver has arrived. OTP: <otp>" | — | OTP by SMS only if rider offline > 60 s |
| STARTED | "Trip started" | — | — |
| COMPLETED | "Trip completed. Fare INR <x>" | "Collect INR <x>" | — |
| PAID (online) | "Payment received" | "Rider paid online" | — |
| CANCELLED | Reason and fee if any | "Ride cancelled by rider" | — |
| NO_DRIVER | "No drivers available right now" | — | — |
| Document approved/rejected | — | Status + note | — |
| Driver suspended | — | "Account paused, contact support" | — |
| SOS | — | — | Admin phone (SMS) + admin WS alert |

FCM: use data + notification payloads; Android channel `rides` (high importance, custom sound for offers). Store and refresh tokens on every app start.

---

# 15. Payments (Razorpay)

1. On COMPLETED with `payment_method = online`, rider app calls `POST /rides/:id/payment/order` → backend creates a Razorpay Order (`amount` in paise, `receipt = ride_id`) and stores `gateway_order_id`.
2. App opens Razorpay Checkout with `key_id`, `order_id`, prefilled phone.
3. On success the app posts the three Razorpay fields to `/payment/verify`; backend verifies HMAC SHA256 of `order_id|payment_id` with key secret, marks payment `paid`, ride `PAID`, emits `payment:status`.
4. Webhook `/webhooks/razorpay` is the source of truth: verify signature, handle `payment.captured` (mark paid if not already) and `payment.failed`. Idempotent by `gateway_payment_id`.
5. A BullMQ job polls Razorpay for any `pending` online payment older than 5 minutes (up to 24 h), then falls back to allowing the driver to mark cash.
6. Refunds: admin-initiated via Razorpay dashboard in MVP; backend exposes no refund endpoint.

**Cash**: driver taps Cash collected → payment `paid` method `cash` → ride `PAID`. Admin can also mark cash.

**Settlements**: Monday 06:00 IST job creates `driver_settlements` for the previous Mon–Sun: `gross_fares` = sum of `final_fare` of PAID rides; `commission` = gross excl. GST × commission_pct; `amount_payable = online_collected − commission − gst_on_gross` (positive: platform pays driver; negative: driver owes platform). Admin marks settled with a reference.

---

# 16. Security and privacy requirements

- JWT access 15 min, refresh 90 days with rotation and reuse detection; refresh tokens hashed in DB (`refresh_tokens` table: id, user_id, token_hash, expires_at, revoked_at, device).
- OTP codes hashed (sha256 + pepper) in Redis; constant-time compare; rate limits as in Section 7.1; generic error messages.
- Role guards on every route; drivers can only act on rides where `driver_id = self`; riders only on `rider_id = self`.
- Input validation on every DTO; reject unknown fields.
- Phone numbers masked in all logs and in rider↔driver payloads until ARRIVED.
- Documents in R2 are private; served via 5-minute signed GET URLs to admins only; ID proof stored as uploaded but only last 4 digits recorded in DB.
- HTTPS only (Caddy, HSTS); CORS restricted to admin origin; Helmet headers; body limit 1 MB.
- Secrets only in environment; `.env` never committed; Sentry scrubs phone and token fields.
- Data retention: `ride_tracks` 30 days; OTP 5 minutes; account deletion endpoint anonymises user (`phone → deleted:<uuid>`, name null) and keeps rides for accounting.
- Audit log for all admin mutations.
- Dependency scanning in CI (`npm audit --audit-level=high`, `flutter pub outdated`).

---

# 17. Deployment

## 17.1 Server

One Ubuntu 24.04 VPS (2 vCPU, 4 GB recommended; 2 GB minimum without OSRM). Docker Engine + Compose plugin. UFW allows 22, 80, 443 only. Fail2ban on SSH. Automatic security updates.

## 17.2 docker-compose.prod.yml (agent generates the full file)

Services: `caddy` (80/443, reverse proxy to `api:3000`, automatic TLS), `api` (NestJS image built in CI, `restart: always`, healthcheck `/health`), `worker` (same image, runs BullMQ processors only: `node dist/worker.js`), `postgres` (postgis/postgis:16-3.4, volume `pgdata`, `shm_size: 256m`), `redis` (redis:7-alpine, `--appendonly yes`, volume), `osrm` (osrm/osrm-backend, `osrm-routed --algorithm mld /data/ncr.osrm`, volume with prepared data, 1.5 GB mem limit), `backup` (alpine cron: nightly `pg_dump | gzip | aws s3 cp` to R2 with 30-day retention).

Caddyfile:
```
api.example.com {
  reverse_proxy api:3000
  encode gzip
}
```

Socket.io needs sticky sessions only with multiple `api` replicas; MVP runs one replica, so none required. If scaling later, add the Redis adapter (`@socket.io/redis-adapter`) — include it from day one behind a flag so scaling needs no code change.

## 17.3 OSRM data preparation (`infra/osrm/prepare.sh`)

1. Download `northern-zone-latest.osm.pbf` (Geofabrik, India/Northern zone) or clip with `osmium extract -b 76.6,28.0,77.9,29.1`.
2. `osrm-extract -p /opt/car.lua ncr.osm.pbf`, `osrm-partition ncr.osrm`, `osrm-customize ncr.osrm`.
3. Store the `.osrm*` files in the `osrm-data` volume. Re-run quarterly.

## 17.4 Admin panel

Built by CI, deployed to Cloudflare Pages (`admin.example.com`), `VITE_API_BASE_URL` set at build time.

## 17.5 Mobile builds

- Flavors: `dev` (points at staging, OTP bypass allowed), `prod`.
- Signing keys generated once, stored by the client (never in repo); CI receives them as base64 secrets.
- Version code auto-incremented from CI run number.
- Play Console: internal testing → closed testing (12 testers, 14 days for new personal accounts) → production. Background-location declaration and demo video for the driver app.

## 17.6 Staging

Same Compose file on the same server with a different project name and `api-staging.example.com`, or a second small VPS. Seeded with test users and `OTP_DEV_BYPASS_CODE`.

## 17.7 Backups and restore

Nightly `pg_dump` to R2 (`backups/ride-YYYY-MM-DD.sql.gz`); weekly restore test into the staging database documented in `docs/RUNBOOK.md`. Redis is ephemeral (driver positions rebuild themselves); AOF only to survive restarts.

---

# 18. CI/CD (GitHub Actions)

- `backend.yml`: on PR → lint, typecheck, unit tests, e2e tests against Postgres+Redis service containers, `prisma migrate diff` check. On push to `main` → build image, push to GHCR, SSH deploy: `docker compose pull && docker compose up -d api worker && docker compose exec api npx prisma migrate deploy`.
- `apps.yml`: on PR → `flutter analyze`, `flutter test` for both apps and shared package. On tag `rider-v*` / `driver-v*` → build signed AAB and APK, upload as artifacts, optionally publish to Play internal track via `r0adkll/upload-google-play`.
- `admin.yml`: lint, typecheck, build; deploy to Cloudflare Pages on `main`.
- Required checks before merge. Conventional commits. `CHANGELOG.md` maintained by the agent per phase.

---

# 19. Testing and quality bar

**Unit tests (Jest)**: fare engine (all branches, night, cap, min fare); state machine transitions (every allowed and several forbidden); cancellation fee rules; matching candidate filtering; OTP verification; Razorpay signature verification; settlement math.

**Integration/e2e (Jest + supertest, real Postgres/Redis in CI)**: full happy path — rider OTP login → driver online → request → offer → accept → arrived → start (OTP) → complete → cash → rating; offer timeout → next driver; no-driver path; concurrent accept by two drivers (only one wins); rider cancel at each stage; webhook idempotency; geofence rejection.

**Load test (k6 script in `backend/test/load`)**: 100 simulated online drivers sending locations every 4 s plus 5 ride requests/min for 10 minutes; API p95 < 300 ms; no dropped offers.

**Flutter**: widget tests for OTP, confirm and offer screens; integration test for the rider booking flow against staging with OTP bypass.

**Manual device matrix before release**: at least one Xiaomi/Redmi, one Samsung, one Vivo/Oppo/Realme phone; Android 10, 12 and 14; test app killed mid-trip, airplane mode for 60 s mid-trip, phone reboot while online.

**Definition of done for every phase**: tests green in CI, no ESLint/analyzer warnings, Swagger updated, `CHANGELOG.md` updated, manual checklist in Section 20 passed on a real device.

---

# 20. Build phases and acceptance criteria

## Phase 0 — Foundation (week 1)
**Scope**: monorepo skeleton; NestJS app with config validation, Prisma schema + migration from Section 5, seed script, `/health`; Docker Compose for dev (postgres, redis, osrm with a tiny test extract); Flutter `shared` package (API client with token refresh, models, theme); rider/driver/admin app shells; CI workflows; `docs/` files.
**Accept**: `docker compose up` gives a healthy API; migrations run; seed creates admin + fare config + NCR polygon; CI green; all three apps build and show a placeholder home.

## Phase 1 — Auth and driver onboarding (weeks 2–3)
**Scope**: OTP send/verify with MSG91 (dev bypass), JWT rotation, admin login; rider profile; driver registration, presigned document upload to R2, document list; admin drivers list/detail/approve/reject/suspend, per-document review; FCM token registration; Sentry.
**Accept**: new rider logs in with OTP on a real phone; driver registers, uploads 6 documents, sees "pending"; admin approves and driver app updates to "approved"; rejected document shows the note; rate limits enforced (6th OTP in an hour rejected).

## Phase 2 — Live location and matching (weeks 4–5)
**Scope**: WebSocket gateway with auth; driver online/offline with foreground service; Redis GEO ingest and heartbeat sweeper; `/drivers/nearby`; geofence; routing service (OSRM + fallback); fare estimate; ride request; matching + offer + timeout jobs; accept/reject with row lock; `ride:status` and `driver:position` streams; rider Finding/Assigned screens; driver offer popup.
**Accept**: with two driver phones online, a ride request reaches the nearer driver first; if ignored 20 s, it goes to the second; accept on both simultaneously → exactly one wins; rider sees the car moving within 2 s of movement; killing the driver app marks it offline within 15 s; pickup outside NCR rejected.

## Phase 3 — Trip lifecycle, fare, ratings (weeks 6–7)
**Scope**: arrived (distance check), OTP start, GPS track ingest, complete with final fare, cancellation rules and fees, driver cancel-count suspension, ratings both ways, ride history and receipts, FCM pushes for all events, share-trip public endpoint and page, SOS endpoint.
**Accept**: 10 real test rides across NCR complete with fares within the estimate cap; wrong OTP blocked; rider cancel after 3 minutes shows the fee and it appears on the next ride; three driver cancels in a day suspends the driver and alerts admin; push notifications arrive with the app in background; share link shows live position.

## Phase 4 — Payments, settlements, admin (weeks 8–9)
**Scope**: Razorpay order/verify/webhook/poll; cash flow; earnings; settlement generation and marking; admin dashboard, live map, rides list/detail/actions (cancel, reassign, adjust fare, mark cash), riders, fare config with preview, service-area editor, reports + CSV, SOS page, audit log.
**Accept**: UPI test payment marks ride PAID via webhook even if the app is closed after paying; duplicate webhook does nothing; settlement for a test week matches a hand calculation; admin reassigns a ride and both drivers' apps update; fare config change applies to the next estimate; CSV export opens in Excel.

## Phase 5 — Hardening and release (weeks 10–11)
**Scope**: load test; edge cases (socket drop, app kill, reboot, airplane mode) fixed; retention job; backups + restore test; production Compose, Caddy, UFW, fail2ban; staging; Play Store listings, privacy policy pages, data-safety form, closed testing; runbook and admin guide with screenshots.
**Accept**: k6 targets met; restore from last night's backup on staging succeeds; both apps in Play closed testing; UptimeRobot and Sentry alerts verified by inducing a failure; `docs/RUNBOOK.md` and `docs/ADMIN_GUIDE.md` complete.

## Phase 6 — Pilot support (weeks 12–14)
**Scope**: bug fixes and UX tweaks from real usage; no new features. Daily check of Sentry, matching failures (`ride_offers` with response timeout ratio), driver offline drops.
**Accept**: 100 completed rides; acceptance within 30 s for 80% of requests; completion rate above 85%; zero fare-calculation disputes.

## Phase 7 — iOS (optional, after pilot)
**Scope**: iOS builds of both apps; background location entitlements; TestFlight; App Store review.

---

# 21. Appendix A — NCR bounding box and seed polygon

Bounding box for Places restriction and OSRM clip: SW (28.20, 76.80), NE (28.95, 77.70). The seed polygon `infra/seed/ncr.geojson` should be a simplified outline (~40 vertices) covering Delhi, Gurugram, Manesar, Faridabad, Noida, Greater Noida and Ghaziabad; refine later with district boundaries from OpenStreetMap.

# 22. Appendix B — Fare examples for tests

| Distance | Duration | Night | Expected estimate (cfg: 50 / 12 / 1.5 / min 80) |
|---|---|---|---|
| 2.0 km | 8 min | no | max(80, 50+24+12=86) = 86 → range 82–95 |
| 10.0 km | 30 min | no | 50+120+45 = 215 → range 204–237 |
| 1.0 km | 4 min | no | max(80, 68) = 80 → range 76–88 |
| 10.0 km | 30 min | yes, ×1.25 | 268.75 → 269 → range 255–296 |
| Final fare, est 215, actual 14 km / 45 min, drop unchanged | | | 50+168+67.5 = 285.5 → capped at 215×1.25 = 268.75 → 269 |

# 23. Appendix C — CLAUDE.md starter

```
# Project rules for the AI coding agent
- Read SPEC.md fully before starting any task. It is the contract.
- Stack, schema, API paths, WebSocket events and state machine are fixed. Propose changes in docs/DECISIONS.md, do not silently diverge.
- Build one phase at a time (SPEC.md Section 20). Do not implement "Later" features.
- Every backend change ships with tests. Run `npm test` and `npm run lint` before declaring done.
- Never commit secrets. Update .env.example when adding config.
- Keep CHANGELOG.md and Swagger in sync with code.
- When unsure about a product rule, ask; when unsure about a library, prefer the one in SPEC.md Section 2.
```
