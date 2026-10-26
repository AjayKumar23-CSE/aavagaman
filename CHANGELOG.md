# Changelog

All notable changes, per build phase (SPEC §18). Conventional commits.

## [Unreleased] — Phase 5: Hardening and release (in progress)

### Added
- **Admin panel (Phase 4 pages)**: Dashboard (today's tiles, rides-by-status chart, backend health), Live map (Leaflet + `admin:live`, drivers by state, active rides, SOS/alert toasts), Rides list and detail (timeline, GPS track, offers, payment; cancel / reassign / adjust fare / mark cash with reason dialogs), Riders (block/unblock), Fare config (history + new version with live preview), Service areas (draw/edit/import GeoJSON), Reports (charts, table, CSV download), Settlements (week navigation, generate, mark settled), SOS (open/acknowledged), Audit log, Settings (password change). Screenshots in `docs/screenshots/`.
- `GET /metrics` (Prometheus text; `METRICS_TOKEN`), nightly `ride_tracks` retention job (`TRACK_RETENTION_DAYS`, 03:00 IST).
- `infra/docker-compose.prod.yml` (caddy, api, worker, postgres, redis, osrm, backup), `infra/Caddyfile`, `infra/backup/` image with nightly `pg_dump` to R2 and a restore script.
- k6 load test (`backend/test/load/`) with an account-seeding script.
- `docs/RUNBOOK.md`: server setup, deploy/rollback, daily checks, backups and restore test, staging, incidents.
- `POST /admin/settings/password` for the Settings page (D-044); public privacy-policy page at `GET /v1/legal/privacy`; `docs/ADMIN_GUIDE.md` and `docs/PLAY_STORE.md` (listing text, data-safety answers, background-location declaration).

### App UI redesign
- Shared design system in `ride_shared` (D-053): Plus Jakarta Sans (bundled, OFL), per-app brand colour (rider blue, driver green) with a saffron accent and success green, rounded cards/inputs/buttons, and reusable widgets (`SoftCard`, `SheetPanel`, `HeroPanel`, `StatusPill`, `IconBadge`, `InitialsAvatar`, `PlateBadge`, `RoutePoints`, `ActionCircle`, `InfoBanner`, `EmptyState`, `StatTile`, `RingProgress`, `KeyValueRow`); dark theme included.
- Login flow (`AuthScaffold`): gradient header with the brand mark, white panel, restyled phone field and OTP boxes.
- Rider: full-bleed map home with floating controls, greeting sheet with search bar, recent-place chips and nearby-cars pill; drawer with gradient header; Confirm with route points, fare card and payment selector; Finding with a countdown ring; Assigned/Trip sheets with driver card, number-plate badge, saffron OTP card and circular Call/Share/SOS; hero headers on Trip completed and Payment received; card-based history and detail; cancelled/no-driver outcome screens.
- Driver: status card that turns green while online, earnings and shortcut tiles; immersive offer popup with amber countdown ring and route points; trip screen with a Pickup · Trip · Payment progress strip, rider card, OTP card and gradient amount panel; earnings with a hero "Today" card; card-based documents, history and profile; verification, suspended and battery screens restyled.
- Screenshot harness (`test/screenshots`, run with `RIDE_SHOTS=<dir> flutter test --update-goldens test/screenshots`) renders every main screen with real fonts for visual checks; skipped in normal test runs.

### Location and confirm screen
- Rider: the position lookup now takes a fresh cached fix straight away, waits for GPS, then falls back to the coarse network fix and finally the last known position (instead of one 8-second GPS attempt that silently fell back to Connaught Place). Fixes stream live afterwards, so the blue dot and the "Current location" pickup follow the rider; the map recentres when the first fix arrives and on the locate button. When no fix can be had the home screen says so, with Retry. Driver app: same GPS → coarse → cached fallback for its one-shot fix.
- Confirm screen: pickup/drop stay pinned at the top of the sheet and the Book button (with any booking error) below it; only the vehicle classes and payment scroll.

### Driver map
- The driver app now opens on a live map, like the rider app: the driver's position (a car while online, so riders can see them), a locate button and the menu float over it, and the status card, earnings and shortcuts sit in a sheet below. The trip screen shows a map card with the car, the pickup (until the trip starts) and the drop, and a dashed guide line to the next stop; Navigate still hands turn-by-turn to Google Maps.
- The map widget (`RideMap`, `RideMapSpec`, markers, `mapBuilderProvider`) moved from the rider app into `ride_shared`, so both apps draw the same map; `google_maps_flutter` is now a `ride_shared` dependency.

### Masked calling (D-058)
- Rider and driver call each other through the Aavagaman number: `POST /rides/:id/call` and `POST /driver/rides/:id/call` ring the caller first and bridge the other party; neither side ever sees the other's phone. Ride payloads carry `call_via` (the virtual number) instead of `phone` while the trip is live when a provider is configured (`CALL_PROVIDER=exotel|stub`); `none` keeps the dialer-after-ARRIVED behaviour. Errors: 409 `RIDE_NOT_CALLABLE`, 429 `CALL_TOO_SOON`, 502 `CALL_FAILED`, 503 `CALLS_UNAVAILABLE`.
- Exotel Connect API client (`EXOTEL_SID/API_KEY/API_TOKEN/SUBDOMAIN/CALLER_ID`), call log table `ride_calls`, outcome webhook `POST /webhooks/calls/exotel?token=CALL_STATUS_SECRET`, and a **Calls** card on the admin ride detail (who called, outcome, talk time). `CALL_MAX_SECONDS` caps a call, `CALL_MIN_INTERVAL_SECONDS` throttles repeats.
- Apps: the Call button is live from the moment a driver is assigned; tapping it shows "Calling you from <number>…"; the driver's trip screen shows "Number private · calls go via Aavagaman" instead of the rider's phone.

### Brand: Aavagaman (D-057)
- The product is now **Aavagaman** ("Safar • Aapke Saath"): app names, Android labels, admin title and Play listing text. Palette from the brand board: deep green `#0F3D2E`, fresh green `#22C55E`, saffron `#F59E0B`, charcoal `#080F14`; riders get the deep-green theme, drivers the leaf-green one; dark mode is charcoal.
- The logo (green "A" with a road climbing to a saffron pin) is drawn in code (`AavagamanMark`, `AavagamanIcon`) and rendered to PNG by `apps/shared/test/branding` for the launcher icons (legacy + adaptive), the native launch screen and `docs/branding/`. The admin panel uses an SVG of the same mark as favicon and sidebar logo.
- Splash screen: the brand board's India Gate sunset picture, full-bleed under the mark and wordmark, with the line "Har safar ka apna ek maqsad hota hai." (`splashQuote` string, `SplashArt` in `ride_shared`, asset `assets/splash_india_gate.jpg`; preview in `docs/branding/splash-1080x2400.png`). The picture is muted and dimmed (`SplashLook.standard`: 70 % saturation under a 34 % charcoal veil) so the mark leads; `docs/branding/splash-looks.png` compares the treatments that were considered (`test/branding/splash_samples_test.dart`). The splash stays up for at least 1.2 s (`splashHoldProvider`) so it is seen even when the session restores instantly. On the splash the mark is alive: the road's dashes travel up towards the pin and the pin sends out a pulse ring (`AavagamanMark(animated: true)`); icons and goldens stay still.
- Loaders in the brand style: `RouteLoader` (rotating arc ending in a pin) on the splash and fare estimate; the "finding your driver" ring now sweeps a green gradient with a pin head. Splash screens show the mark over faint road curves.

### Vehicle classes (D-056)
- Riders choose between **Bike, Auto, Mini and Sedan** on the confirm screen, each with its own fare range. `POST /fare/estimate` returns `options` (one per class with a fare config id) alongside the old top-level sedan fields; `POST /rides` takes `vehicle_type` (default sedan) and refuses a fare config of another class. Matching already filtered by class, so an auto request only reaches auto drivers.
- Fare config is per class: the seed creates a starting version for each (bike 20/6/1 min 30, auto 30/9/1 min 40, mini 40/10/1.25 min 60, sedan unchanged), the admin Fare config page has a tab per class, and `GET /admin/fare-config` returns `current_ids` per class.
- Drivers pick their vehicle class at registration (`vehicle.vehicle_type`); admins can change it in the vehicle dialog. `GET /drivers/nearby` includes `vehicle_type`.

### Broadcast matching (D-055)
- A ride request now goes to the nearest `OFFER_BATCH_SIZE` free drivers **at the same time** (default 5) instead of one driver after another; a driver can hold requests from several rides and picks one. First accept wins; the other offers of that round and the winner's offers from other rides are closed as `withdrawn` (new `offer_response` value, migration `20261017000000_offer_withdrawn`). A round ends when everyone has answered or after `OFFER_TIMEOUT_SECONDS`; the next round asks drivers not yet offered that ride; `MAX_OFFER_ROUNDS_PER_RIDE` (default 3) rounds, or the 2-minute deadline, end in NO_DRIVER. `MAX_OFFERS_PER_RIDE` is gone. Redis: `ride:{id}:offers` hash and `driver:{id}:offers` set replace the single-offer keys; the driver `offered` state now only colours the admin map.
- Driver app: the request screen lists every open request as a card with its own countdown, distance, fare and Accept/Reject; the tone plays while any request is open. On reconnect the server re-sends every open offer.
- Admin ride detail shows `withdrawn` offers.

### Admin panel through a tunnel
- `ADMIN_ORIGIN` accepts a comma-separated list of origins (CORS for REST and the `/rt` socket), so a deployed or tunnelled panel and `http://localhost:5173` work at the same time (D-054).
- The panel sends `ngrok-skip-browser-warning` on API calls when its API base URL is an ngrok host (ngrok's free tier otherwise answers browser fetches with its warning page; WebSockets are unaffected). `vite preview` allows ngrok hostnames so the production build can be served through a tunnel.

### Routing
- The Google fallback for routes now uses the **Routes API** (`computeRoutes`, traffic-aware) instead of the legacy Directions API, which new Google Cloud projects cannot enable (D-052). Verified with real NCR estimates.

### Android builds
- First real builds: `dev` release APKs for both apps, signed with a test key. Driver app: core-library desugaring and `compileSdk` 37 (needed by `flutter_local_notifications` and `permission_handler_android`).

### Storage
- Amazon S3 as well as Cloudflare R2 for driver documents: new `S3_REGION` (default `auto` for R2); with no `S3_ENDPOINT` the API signs for Amazon S3 in that region (D-051). Verified end to end against a private S3 bucket: presigned upload from the driver flow, signed 5-minute view link for the admin, unsigned access refused.

### Driver licence checks
- Drivers give their **date of birth** at registration (`date_of_birth`, required; 422 `DATE_OF_BIRTH_INVALID` under 18). Migration `driver_date_of_birth`. Driver app: date-of-birth field (18+ only) on Registration, shown on Profile.
- Offline **licence-number format check** (state code, RTO, year of issue, issued before 16): `licence_check` on `GET /admin/drivers/:id`, `licence_flagged` on the drivers list. It warns, never refuses (D-050).
- Admin panel: *Licence check* card with copy buttons and **Check on Parivahan** (opens the official licence-status page with the number copied); *Check licence* badge in the drivers list. Admin guide updated.
- Privacy page, driver-app privacy text and Play data-safety notes list the date of birth.

### Apps (Phase 3–4 screens)
- **Shared**: trip, payment, rating, history, receipt, earnings and SOS endpoints on `RideApi` / `PaymentsApi`; `Receipt`, `DriverEarnings`, `RatingResult` and per-trip `RideEarning` models; `SosFlow` (dial 112 first, then `POST /rides/:id/sos`); `StarRating` widget; fixtures captured from the live API.
- **Rider**: Trip in progress (route, live car, Call / Share trip / SOS), Fare & payment (receipt breakdown with carried-over cancellation fee; cash → wait for the driver; online → Razorpay Checkout → verify, with retry or switch to cash, and recovery when the ride was paid while the app was away), Rate (stars, comment, skip), drawer → Ride history with load-more and Ride detail/receipt.
- **Driver**: full trip screen: Arrived (server distance check message), 4-digit OTP entry → Start trip, Navigate to drop, End trip (confirm), Collect payment (amount due, cash collected with confirm, "waiting for online payment" until `payment:status`, cash as fallback), Rate the rider (skip allowed), Cancel with a reason picker (no-show unlocked after 5 min at the pickup), SOS in the app bar. Drawer → **Earnings** (today/week cards: net, fares, commission, GST, cash, online; recent trips with fare, commission, GST and net) and **Trip history**; Home shows today's net earnings.
- Android: `dev` (default, `.dev` package) and `prod` flavors; release builds signed with the upload key from `key.properties` or CI secrets; `apps.yml` release job builds a signed `prod` AAB/APK and refuses to run without the keystore secret.
- Tests: shared 140, rider 38, driver 44; zero analyzer issues with `--fatal-infos`.

### Changed
- `GET /driver/rides` items carry `earning: {fare, commission, gst, net}` once a ride has a final fare (D-047).

### Fixed
- Driver app: going offline from a disposed presence controller read a provider during dispose (Riverpod assertion), so the location foreground service could be left running; the feed is now captured when the controller is built.
- Driver app: a PAID ride went straight to "This ride has ended"; it now shows the rating step first.

## Phase 4: Payments, settlements, admin

Backend. Admin panel pages and the apps' payment screens follow.

### Added
- **Razorpay** (SPEC §15): `POST /rides/:id/payment/order` (Orders API, amount in paise, idempotent while pending), `POST /rides/:id/payment/verify` (HMAC of `order_id|payment_id`), `POST /webhooks/razorpay` (raw-body signature check; `payment.captured` / `payment.failed`; idempotent on `gateway_payment_id`), a poll job for captures the webhook missed, and a cash fallback rule (`PAYMENT_CASH_FALLBACK_SECONDS`). `payment:status` events for paid/failed.
- `POST /admin/rides/:id/mark-cash` sharing the driver's cash-collected path.
- **Earnings** `GET /driver/earnings?period=today|week` and **settlements**: Monday 06:00 IST job, `GET /admin/settlements?week=`, `POST /admin/settlements/generate`, `POST /admin/settlements/:id/settle`; pure settlement maths unit-tested.
- **Admin**: `GET /admin/dashboard`, `GET /admin/live` + `admin:live` every 2 s while an admin is connected, rides list/detail (events, offers, payment, track GeoJSON), reassign, adjust-fare, riders list/block/unblock, fare config list/create/preview, service areas as GeoJSON (list/create/patch with PostGIS validation), daily report (JSON/CSV), SOS list/ack, audit log.
- e2e: Phase 4 acceptance scenarios against a fake Razorpay.

## Phase 3: Trip lifecycle, fares, ratings

Backend. The rider/driver trip screens follow once the Phase 2 app screens land.

### Added
- **Trip lifecycle** (SPEC §7.3, §10): `POST /driver/rides/:id/arrived` (422 `TOO_FAR_FROM_PICKUP` beyond `ARRIVAL_RADIUS_M`), `/start` (constant-time 4-digit OTP; 401 `OTP_INVALID` with attempts left, `OTP_LOCKED` after 3 and an `admin:alert`), `/complete` (final fare from the GPS track with the §9.3 filters and OSRM fallback, capped at 125 % of the estimate), `/cancel` (reason mandatory), `/cash-collected` (payment row, ride `PAID`, driver idle, `payment:status` to both parties).
- **GPS tracks**: every driver fix during a ride is stored in `ride_tracks`; "Your driver is nearby" push once within 300 m of the pickup.
- **Cancellation rules** (§9.5): rider free within `FREE_CANCEL_WINDOW_SECONDS` of acceptance, fee afterwards or after ARRIVED; the fee is carried onto the rider's next completed ride (`cancellation_fee` line item, `fee_applied_to_ride_id` marks it collected); driver cancel re-queues the ride excluding that driver and counts towards a daily limit (`DRIVER_CANCEL_SUSPEND_AT` → auto-suspension + admin alert); driver no-show cancel after `NO_SHOW_WAIT_SECONDS` charges the rider and is not counted; `POST /admin/rides/:id/cancel` with a mandatory reason, audited.
- **Ratings both ways**: `POST /rides/:id/rating`, `POST /driver/rides/:id/rating`; `users.rating_avg/rating_count` updated atomically; one rating per party per ride.
- **History and receipts**: `GET /rides`, `GET /driver/rides` (paginated), `GET /rides/:id/receipt` (components, GST-inclusive fare, cancellation fee line, total, payment status).
- **Share trip**: `GET /v1/share/:token` — public; JSON for apps, a Leaflet tracking page for browsers.
- **SOS**: `POST /rides/:id/sos` for the rider or driver of the ride → `sos_alerts`, `sos:alert` to admins, SMS to admin phones.
- OTP SMS fallback job: trip OTP texted if the rider's app is offline `OTP_SMS_FALLBACK_SECONDS` after ARRIVED.
- Migration `phase3_trip`: `rides.otp_attempts`, `rides.fee_applied_to_ride_id`.
- e2e: Phase 3 acceptance scenarios (full lifecycle, fee carry-over, re-queue + suspension, no-show, OTP lock, SMS fallback, share, SOS, admin cancel).

### Changed
- Admin reject/suspend and document reject now require a `note` (SPEC §13).
- Presigned uploads no longer carry a default CRC32 checksum; `Content-Type` is signed.
- `PATCH /me` accepts `email: null` to clear the email.
- Document review is limited to the latest upload of a type (409 `NOT_LATEST_DOCUMENT`).

## Phase 2: Live location and matching

### Apps
- **Shared**: ride models (`Ride`, `RideOffer`, `FareEstimate`, …) with `Ride.apply(event)`, `RideApi`, `RealtimeClient` (typed streams, acks, backoff, re-auth on `UNAUTHORIZED`), Google Places (New) client with NCR bounds and session tokens, map config, single-flight `TokenRefresher` shared by REST and socket, fake socket for tests; 30 fixtures captured from the live API.
- **Rider**: map home (GPS or Connaught Place fallback, nearby cars every 10 s), drop search with recents and pick-on-map, Confirm (fare range, cash/online, out-of-area notice), Finding (2-minute ring, cancel, no-driver), Assigned/En route (driver card, live car with ETA, large OTP, Call after arrival, cancel-fee warning), resume via `GET /rides/active` + `rider:subscribe`.
- **Driver**: Online/Offline switch with a foreground-service location feed (4 s / 2 s, accuracy filter, REST batch fallback, re-online on `DRIVER_OFFLINE`), offer popup (countdown ring, tone, vibration, full-screen-intent notification, accept via socket with REST fallback), Navigate-to-pickup screen, battery-optimisation guide for Xiaomi/Vivo/OPPO/Realme/Samsung, Android permissions and service declaration.
- Tests: shared 108, rider 28, driver 33, zero analyzer issues.

### Backend

### Added
- **WebSocket gateway** (`/rt`, Socket.io, SPEC §8): JWT handshake, `user:{id}` and `admin` rooms, active ride (and any open offer) re-sent on connect; `driver:location`, `driver:offer:accept`, `driver:offer:reject`, `rider:subscribe`, `admin:subscribe` with acknowledgements in the REST error shape. Redis adapter + emitter so the worker process can reach clients.
- **Driver presence** (SPEC §6, §7.3): `POST /driver/online` (403 unless approved with all mandatory documents valid), `POST /driver/offline` (409 on a trip), `POST /driver/location`; Redis GEO set, heartbeat key, driver state, cached position; heartbeat sweeper every 10 s marks silent drivers offline and times out their open offer.
- `GET /drivers/nearby` — up to 10 idle cars, anonymised.
- **Geofence** (`ST_Covers` on active service areas) and **routing** (OSRM → Google Directions fallback → 503 `ROUTING_UNAVAILABLE`, 60 s Redis cache).
- **Fare engine** (`fare.engine.ts`, pure, unit-tested against SPEC Appendix B) and `POST /fare/estimate`.
- **Rides**: `POST /rides` (geofence, server-side route + estimate, 4-digit OTP, share token, one active ride per rider), `GET /rides/active`, `GET /rides/:id`, `POST /rides/:id/cancel` while searching; `GET /driver/rides/active`, `POST /driver/rides/:id/accept|reject`.
- **Matching** (BullMQ, SPEC §9.4): nearest idle driver first, 20 s offers, radius 3 → 5 km, up to 3 offers within 2 min, `NO_DRIVER` otherwise; accept takes a row lock so concurrent accepts yield exactly one winner; rider cancel withdraws the pending offer and jobs.
- **Ride state machine** (`ride-state.ts`) enforcing SPEC §10; every transition writes `ride_events`, emits `ride:status` and sends the matching FCM push.
- Separate **worker** entry point (`dist/worker.js`) running the BullMQ processors (SPEC §17.2).
- Migration `ride_payment_method`: `rides.payment_method` (`cash` | `online`).
- e2e: Phase 2 acceptance scenarios against a fake OSRM, with shortened timers.

### Fixed
- Config loading no longer writes to the host environment (it leaked the dev `.env` into later Jest test files, which then ran against the dev database).

## Phase 1: Auth and driver onboarding

### Added
- **Auth** (SPEC §7.1, §16): phone OTP (MSG91 with a log fallback outside production; dev bypass code), hashed single-use OTPs with attempt lock and rate limits (5/h per phone, 3/min per IP), JWT access tokens, rotating hashed refresh tokens with reuse detection, logout, admin email + password login (argon2id, lockout after 10 failures).
- Global auth guard with role decorators; `@Public()` for open routes.
- **Rider profile**: `GET/PATCH /me`, `POST /me/fcm-token`, `DELETE /me` (anonymises the account).
- **Driver onboarding** (SPEC §7.3): `POST /driver/register`, presigned R2 uploads (`POST /driver/documents/presign` + `POST /driver/documents`), `GET /driver/me` with eligibility (`can_go_online`, missing and expired documents).
- **Admin drivers** (SPEC §7.4): list with filters and search, detail with 5-minute signed document URLs and ride stats, approve / reject / suspend / reinstate, per-document approve / reject (latest upload only), vehicle edit. Every mutation is audited and pushed to the driver.
- FCM push service (never fails a request; clears stale tokens) and Sentry with phone/token scrubbing.
- **Admin panel**: login with token refresh and route guard, drivers list (tabs, search, pagination, IST times) and driver detail (profile, vehicle edit, document viewer with per-document review, confirm dialogs with mandatory reasons).
- **Flutter**: shared auth session controller, OTP/phone widgets, typed API repositories and models; rider Phone → OTP → Name → Home with profile drawer and delete account; driver Phone → OTP → Registration → Documents (camera/gallery, ≤ 800 KB JPEG, presigned PUT) → Pending approval (polls, shows reviewer notes) → Home; Android platform folders generated (debug-only cleartext, permissions); FCM and Sentry wired behind try/catch and `--dart-define`.
- e2e: Phase 1 acceptance scenarios (OTP login, 6th OTP rejected, onboarding, approval flow, rejected-document note, token rotation).

### Changed
- Backend upgraded from NestJS 10 to NestJS 12 (D-003); Jest runs through `@swc/jest`.

## Phase 0: Foundation

### Added
- Monorepo skeleton per SPEC §3: `backend/`, `apps/{rider,driver,shared}`, `admin/`, `infra/`, `docs/`, CI workflows.
- Backend (NestJS):
  - zod env validation that fails fast and lists every missing variable
  - `/v1` prefix, error shape `{error:{code,message}}`, ValidationPipe that rejects unknown fields
  - helmet, CORS limited to the admin origin, 1 MB body limit
  - pino logs with phone and token redaction
  - Swagger at `/docs`
  - `GET /health` reporting db, redis and osrm
- Prisma schema and initial migration for every SPEC §5 table and enum, plus `refresh_tokens` (§16), the partial unique indexes and the GIST indexes.
- Idempotent seed: admin user, fare config (50 / 12 / 1.5 / min 80, cancellation 30, commission 15) and the Delhi NCR service area (`infra/seed/ncr.geojson`, 38 vertices).
- Dev Docker Compose: PostGIS 16, Redis 7, OSRM with an auto-built Delhi extract, and the API. The API migrates and seeds on start.
- `infra/osrm/prepare.sh` for production OSRM data.
- Flutter `ride_shared` package: dio API client with single-flight token refresh, secure token store, SPEC error parsing, models and Material 3 theme.
- Rider and driver app shells: Riverpod, go_router, ARB localisation, and a placeholder home that shows API health.
- Admin shell: React, Vite, Tailwind, TanStack Query and react-router, with a placeholder home that shows API health (times in IST).
- CI:
  - `backend.yml`: lint, typecheck, unit tests, audit, migrate + seed, e2e, migration drift check, GHCR image, gated SSH deploy
  - `apps.yml`: analyze, test, tagged release builds
  - `admin.yml`: lint, typecheck, build, audit, gated Cloudflare Pages deploy
