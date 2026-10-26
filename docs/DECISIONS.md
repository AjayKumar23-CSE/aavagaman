# Architecture decision log

Deviations from, or clarifications of, SPEC.md. Every entry must justify itself against the spec.

| ID | Date | Status |
|---|---|---|
| D-001 … D-011 | 2026-09-28 | Accepted (Phase 0) |
| D-012 … D-020 | 2026-09-28 | Accepted (Phase 1) |
| D-021 … D-028 | 2026-10-04 | Accepted (Phase 2) |
| D-029 … D-035 | 2026-10-04 | Accepted (Phase 3) |
| D-036 … D-041 | 2026-10-04 | Accepted (Phase 4) |
| D-042 … D-045 | 2026-10-04 | Accepted (Phase 5) |
| D-046 | 2026-10-04 | Accepted (apps, Phase 2) |

---

### D-001 — Repository location
The monorepo lives at `tinkai_code/ride-platform/` as its own git repository (default branch `main`, per SPEC §18).

### D-002 — Prisma 6, not Prisma 7
SPEC §2 says "Prisma preferred" without a version. Prisma 7 requires driver adapters and a `prisma.config.ts`, and changes client generation. Prisma 6.19 keeps `url = env("DATABASE_URL")` and the `Unsupported("geography(...)")` workflow that SPEC §5 describes. Revisit after the pilot.

### D-003 — NestJS 12 instead of NestJS 10
SPEC §2 fixes NestJS 10, but it is past its support window. Its dependency tree also failed the §16 CI gate (`npm audit --audit-level=high`), with some advisories fixed only in Nest 11+. **Decided 2026-09-28: upgrade to NestJS 12** (`@nestjs/*@12`, `@nestjs/swagger@12`, `nestjs-pino@5`).
- Nest 12 packages are ES modules. The backend stays CommonJS and relies on Node's `require(esm)`, which is why `engines.node` is **>=22.12**.
- Jest (SPEC §19) runs through `@swc/jest` and also transforms `node_modules/@nestjs` (see `transformIgnorePatterns`), so tests stay on Jest.
- The remaining `overrides` are `deepmerge-ts` (via `@prisma/config`) and `uuid` (via `firebase-admin` → `gaxios`). `npm audit --omit=dev` reports 0 vulnerabilities.

### D-004 — Indexes Prisma cannot model live only in SQL
`one_active_vehicle_per_driver` and `one_active_ride_per_driver` are partial unique indexes. `service_areas_gix` and `rides_pickup_gix` are GIST indexes on PostGIS columns. They are appended by hand to the init migration exactly as in SPEC §5.
- `backend/scripts/check-migrations.sh` (the CI drift check from SPEC §18) ignores a `DROP INDEX` for these four indexes and fails on any other drift.
- **When generating a migration** (`prisma migrate dev --create-only`), delete any `DROP INDEX` lines for these four indexes before applying it.

### D-005 — System routes outside `/v1`
`GET /health` and `GET /metrics` are served at the root, not under `/v1`. They are infrastructure endpoints for Docker and Caddy healthchecks and UptimeRobot. `/health` returns **503** when `db` or `redis` is down. `osrm:false` alone keeps `status:"ok"`, because routing falls back to Google Directions (SPEC §9.2).

### D-006 — `refresh_tokens` table
SPEC §16 requires it but §5 has no DDL for it. Columns follow §16: `id, user_id, token_hash (unique), expires_at, revoked_at, device (JSONB)`, plus `created_at`.

### D-007 — Config additions
`.env.example` gains three things:
- `ENABLE_DOCS`, which SPEC §7 mentions but §4 does not list.
- `SEED_ADMIN_EMAIL`, `SEED_ADMIN_PASSWORD` and `SEED_ADMIN_PHONE`, which the seed script uses. `users.phone` is `NOT NULL`, so the admin needs a phone.
- `SEED_NCR_GEOJSON`, an optional path override used in containers.

The env schema also refuses to boot with `OTP_DEV_BYPASS_CODE` set when `NODE_ENV=production`.

### D-008 — Dev OSRM extract
SPEC Phase 0 asks for "osrm with a tiny test extract". Dev compose downloads BBBike's `NewDelhi.osm.pbf` (about 37 MB) and builds MLD data automatically, using one-shot init services. Production follows SPEC §17.3 (`infra/osrm/prepare.sh`: Geofabrik northern zone clipped to the NCR bbox).

### D-009 — Flutter secure token storage
The shared package stores JWTs with `flutter_secure_storage`, which is not listed in SPEC §2. Refresh tokens last 90 days and must not sit in plain SharedPreferences.

### D-010 — Flutter platform folders are generated
`apps/rider` and `apps/driver` contain `lib/`, `test/` and `pubspec.yaml` only. Android folders come from `flutter create` (see README) and are committed after the first generation. Flavors (`dev`/`prod`, SPEC §17.5) are added with the Android folders.

### D-011 — Tooling versions
- Backend: NestJS 12 (D-003), Prisma 6 (D-002), Jest 29 through `@swc/jest`.
- ESLint 10 (flat config), because ESLint 9 is deprecated.
- Admin: Vite 8, React 19, react-router 8, Tailwind 4 (`@tailwindcss/vite`), TanStack Query 5.
- Flutter: Riverpod 3, go_router 18, dio 5, which need Flutter 3.44 or later.
- Node 22 in Docker and CI, per SPEC §2.

---

## Phase 1

### D-012 — Anonymised phone fits VARCHAR(15)
SPEC §16 says deletion sets `phone → deleted:<uuid>`, but `users.phone` is `VARCHAR(15)` (§5). The placeholder is therefore `del:` followed by 11 random base64url characters. Deletion also clears name, email and FCM token, sets `status = blocked`, revokes refresh tokens, and is refused with 409 `ACTIVE_RIDE` during a ride. The endpoint is `DELETE /v1/me`; §7 lists none, but §11 and §16 require one.

### D-013 — Mandatory driver documents
The Phase 1 acceptance test uploads "6 documents", and `doc_type` has 7 values. The mandatory set is `driving_licence, rc, insurance, permit, id_proof, selfie`; `fitness` is optional. Expiry dates are required for `driving_licence, insurance, permit, fitness`. A document expiring today is still valid; dates are compared in IST.

### D-014 — `id_last4` supplied with the ID proof upload
SPEC §16 says to record only the last 4 digits of the ID, but no endpoint carries them. `POST /driver/documents` accepts optional `id_last4` and requires it when `doc_type = id_proof`.

### D-015 — Driver verification transitions
- approve: from pending or rejected
- reject: from pending or approved
- suspend: from approved
- reinstate: from suspended; this also resets `cancel_count_today`

Approve and reinstate require every mandatory document to be approved and unexpired, plus a completed profile; otherwise the API returns 422 `DOCUMENTS_INCOMPLETE`. A rejected driver who re-registers or re-uploads goes back to `pending`. Invalid transitions return 409 `INVALID_TRANSITION`. Every action is audited and pushed to the driver.

### D-016 — Auth details the spec leaves open
- OTPs are 6 digits (the dev bypass `123456` is 6). They are stored as `sha256(OTP_PEPPER:phone:code)`, single-use, and locked after `OTP_MAX_ATTEMPTS` wrong tries. All failures return the same `OTP_INVALID`.
- `OTP_PEPPER` is a new required variable. Production also requires `MSG91_AUTH_KEY` and `MSG91_TEMPLATE_ID`. The dev bypass is ignored when `NODE_ENV=production`.
- A phone belongs to exactly one role. Logging in with the other app returns 403 `ROLE_MISMATCH`.
- Refresh tokens are opaque random strings stored as `HMAC(JWT_REFRESH_SECRET)`. Rotation is claimed atomically; any reuse, including a concurrent double refresh, revokes all of the user's tokens.
- Logout revokes **all** of the user's refresh tokens, as well as clearing `fcm_token`.
- Admin lockout: after 10 failures per email the account is locked for 15 minutes (429 `ACCOUNT_LOCKED`). Unknown emails take the same argon2 time as wrong passwords.
- The API trusts `X-Forwarded-For` only from loopback and private ranges (Caddy on the Docker network).

### D-017 — List response shape
Paginated lists return `{ data: [...], page, limit, total }`. SPEC §7 fixes the query parameters but not the response shape.

### D-018 — Presign response adds `expires_in`
`POST /driver/documents/presign` returns `{upload_url, file_key, expires_in: 600}`, a superset of §7.3. Keys are `drivers/<driver_id>/<doc_type>/<uuid>.<ext>`, and `POST /driver/documents` rejects a key outside that prefix. Allowed types are `image/jpeg`, `image/png` and `application/pdf`.

### D-019 — Push and SMS never fail a request
`PushService` logs and swallows FCM errors and clears stale tokens. Without `FCM_SERVICE_ACCOUNT_JSON_BASE64` it only logs. Outside production, the SMS provider falls back to logging the OTP (the code itself is shown only when `NODE_ENV=development`).

### D-020 — Admin detail exposes the document history
`GET /admin/drivers/:id` returns the profile plus `document_history` (every upload, newest first, each with a 5-minute signed `view_url`), `selfie_url`, `id_last4` and ride stats. A signing failure (for example, storage not configured) yields `null` URLs rather than an error.

---

## Phase 2

### D-021 — `rides.payment_method` column
SPEC §7.2 sends `payment_method: "cash" | "online"` with `POST /rides`, but §5 has no column for it and `payments.method` is only created at payment time. Migration `ride_payment_method` adds `rides.payment_method` (`ride_payment` enum, default `cash`). It drives the COMPLETED → payment flow in Phase 4.

### D-022 — Socket.io through Redis from day one
SPEC §17.2 says to include the Redis adapter behind a flag. It is always on instead: the **worker** process (matching jobs, heartbeat sweeper) must reach connected clients, and it has no Socket.io server. The API uses `@socket.io/redis-adapter`; both processes emit through `@socket.io/redis-emitter` (`RealtimeEmitter`). The adapter key is namespaced by Redis DB number so test and dev never cross-talk. Multiple API replicas need only sticky sessions.

### D-023 — BullMQ job ids use `_` not `:`
SPEC §9.4 names jobs `match:{ride_id}` and `offer:{ride_id}:{driver_id}`; BullMQ rejects custom ids containing `:`. They are `match_{ride_id}_{attempt}` and `offer_{ride_id}_{driver_id}`. The current match job id is also stored in `ride:{id}:match` so a rider cancel can remove it.

### D-024 — Nearby cars are anonymised with a rotating token
`GET /drivers/nearby` must not let a rider track a specific driver. `driver_id` in that response is the first 16 hex chars of `HMAC(JWT_ACCESS_SECRET, "<driver_id>:<YYYY-MM-DD>")`, stable within a day and useless across days. Only `idle` drivers are listed.

### D-025 — `.env` is merged into `process.env`, never the host environment
`process.loadEnvFile` writes to the host environment, which Jest copies into every later test file; the second e2e file then ran against the dev database. `loadConfig()` now parses `.env` with `util.parseEnv` and assigns with `??=` (existing variables win). `test/e2e/setup-env.ts` loads `.env.test` the same way.

### D-026 — Rejecting or suspending needs a reason
SPEC §13 requires a reason on every destructive admin action. `POST /admin/drivers/:id/reject`, `/suspend` and `/documents/:docId/reject` now require `note` (1–500 chars). Approve and reinstate keep it optional.

### D-027 — Presigned PUTs carry no default checksum, and sign Content-Type
AWS SDK v3 adds `x-amz-checksum-crc32` for the *empty* body to presigned `PutObject` URLs by default, so the real upload would fail against R2. The `S3Client` sets `requestChecksumCalculation: 'WHEN_REQUIRED'`. `content-type` is a signable header, so the app must upload the type it declared.

### D-028 — Known gaps carried to later phases
- `POST /driver/documents` does not verify that the object exists in R2 (an unuploaded `file_key` is accepted; the admin sees "preview unavailable" and rejects). A `HeadObject` check is planned for Phase 5 hardening once a bucket exists.
- Uploading a `driving_licence`, `insurance`, `permit` or `fitness` document deliberately overwrites the matching expiry on `drivers` / `vehicles` (SPEC §1.1 expiry tracking), including the licence expiry given at registration.
- Phone numbers in Phase 2 payloads stay masked until ARRIVED (SPEC §16); the admin always sees full numbers.
- Phase 2 only allows rider cancellation while `REQUESTED`. Fees and later-stage cancellation arrive with Phase 3 (SPEC §9.5).

---

## Phase 3

### D-029 — One share URL for apps and browsers
SPEC §7.2 defines `GET /share/:token` (JSON) and §20 asks for "a page". Both live at `GET /v1/share/:token`: a request whose `Accept` prefers `text/html` gets a small Leaflet + OpenStreetMap tracking page (nonce-based CSP, no API keys), which polls the same URL with `Accept: application/json` every 5 s. The JSON adds `eta_s`, pickup and drop coordinates; it never contains the rider's identity or any phone number. The URL the rider shares is `<API_BASE_URL>/v1/share/<token>`.

### D-030 — SOS for the driver too
§7.2 lists `POST /rides/:id/sos` under the rider, while §12 gives the driver an SOS button. The endpoint accepts either party of the ride (anyone else gets 404). Admins get `sos:alert` over WebSocket and an SMS to every active admin phone (`MSG91_ALERT_TEMPLATE_ID`; logged when unset).

### D-031 — Cash collection lands in Phase 3
`POST /driver/rides/:id/cash-collected` (SPEC §15 "Cash") ships with the trip lifecycle: without it a driver would stay `on_trip` forever after a completed ride. It creates/updates the `payments` row (`cash`, `paid`, `amount = final_fare + cancellation_fee`), moves the ride to PAID, frees the driver and emits `payment:status`. Razorpay and admin "mark cash" remain Phase 4.

### D-032 — Carried-over cancellation fees
§9.5 says a fee is "added as a line item to the rider's next completed ride (`rides.cancellation_fee` on that ride, from a `pending_fees` lookup)". The lookup is: the rider's CANCELLED rides with `cancellation_fee > 0` and `fee_applied_to_ride_id IS NULL`. On completion their fees are summed into the new ride's `cancellation_fee` and they are stamped with `fee_applied_to_ride_id`. So `cancellation_fee` means "fee charged for this cancellation" on a CANCELLED ride and "fees collected here" on a COMPLETED/PAID ride; `amount_due = final_fare + cancellation_fee` is what the rider pays and what the payment row carries.

### D-033 — Trip rules are environment settings for now
§7.3 calls the 300 m arrival radius "admin-configurable". There is no settings table in §5, so `ARRIVAL_RADIUS_M`, `FREE_CANCEL_WINDOW_SECONDS`, `NO_SHOW_WAIT_SECONDS`, `DRIVER_CANCEL_SUSPEND_AT`, `OTP_START_MAX_ATTEMPTS` and `OTP_SMS_FALLBACK_SECONDS` are environment variables with the spec's defaults. An admin settings page can move them into the database later without changing the services.

### D-034 — Track timestamps, OTP attempts and admin alerts
- `ride_tracks.recorded_at` uses the client fix timestamp when it is within 2 minutes of server time, otherwise server time; duplicates are ignored. Points are stored from acceptance onwards; only points between `started_at` and `completed_at` count towards distance.
- Wrong OTP attempts are counted in `rides.otp_attempts` and recorded as `ride_events` rows (ARRIVED → ARRIVED, `meta.type = otp_failed`). After `OTP_START_MAX_ATTEMPTS` the ride is flagged and `start` returns 401 `OTP_LOCKED`.
- "Admin notified" (suspension, OTP lock) is the WebSocket event `admin:alert {type, …, at}` to the admin room; §8 defines no such event.

### D-035 — Driver cancellation re-queue details
A counted driver cancel sets the ride back to REQUESTED with `driver_id`, `vehicle_id`, `accepted_at`, `arrived_at` cleared and `otp_attempts` reset, keeps the trip OTP, adds the driver to the ride's `offered_set`, and restarts matching with a fresh 2-minute deadline and offer budget (offers before the restart are not counted). The daily counter resets by IST date. Suspension happens only for `approved` drivers and also takes them offline.

---

## Phase 4

### D-036 — Payment rows and methods
`payments.method` is NOT NULL but unknown when a Razorpay order is created, so an online attempt is stored as `upi` (provisional) and corrected from the gateway's `method` on capture (`upi` → upi, `wallet` → wallet, everything else → `card`, since the §5 enum has no netbanking/EMI). `payments.amount` is `final_fare + cancellation_fee`. A rider may pay online even if the ride was booked as cash: the order endpoint only requires `COMPLETED`.

### D-037 — Cash after an online attempt
§15 step 5 polls pending online payments older than 5 minutes "then falls back to allowing the driver to mark cash". Implemented as: cash (driver or admin) is refused with 409 `PAYMENT_PENDING` while an online attempt is pending **and** younger than `PAYMENT_CASH_FALLBACK_SECONDS` (default 300); a failed attempt or an older pending one no longer blocks it. The poll job runs every `PAYMENT_POLL_INTERVAL_SECONDS` and only looks at pending orders between 5 minutes and `PAYMENT_POLL_MAX_HOURS` old. A capture arriving after the ride was already paid (e.g. cash meanwhile) is recorded on the payment row and raises `admin:alert payment_after_close` / `double_payment` instead of changing the ride.

### D-038 — Webhook raw body
Signature verification needs the exact bytes, so the JSON body parser keeps `req.rawBody` for every request (express `verify` hook). Webhooks are public, return 400 on a bad signature, and otherwise 200 with `{ok, result}` even for unknown orders, so Razorpay does not retry forever.

### D-039 — Settlement arithmetic and carried fees
`gross_fares` = Σ `final_fare`; `commission` = Σ commission on the fare excluding GST; `gst_on_gross` = Σ GST contained in the fares; `cash_collected` / `online_collected` = Σ `payments.amount` by method, which includes carried-over cancellation fees. Hence `amount_payable = online_collected − commission − gst_on_gross` as in §15, and a cancellation fee ends up with the driver who completed the ride that collected it (MVP simplification). Periods are Mon–Sun by IST, rides are attributed by `paid_at`, settled rows are never regenerated, and `generate` refuses a week that has not ended (422 `WEEK_NOT_OVER`). `GET /driver/earnings` reports `net = gross − commission − gst` plus the same cash/online split.

### D-040 — Admin surfaces beyond the §7.4 table
- `POST /admin/fare-config/preview` runs the fare engine on a draft config (for the §13 preview calculator); nothing is stored.
- Service areas are exchanged as GeoJSON (`FeatureCollection` out, `Polygon` in) and validated with `ST_IsValid`; `PATCH` can rename, toggle `active` or replace the polygon.
- `GET /admin/reports/daily` aggregates per IST day: requested/completed/cancelled/no-driver counts by `requested_at`, money by `paid_at`; `format=csv` returns `text/csv` with CRLF line endings.
- Riders are blocked by setting `users.status = blocked` and revoking their refresh tokens; existing access tokens expire naturally (15 min). Blocking needs a reason.
- Reassign requires the target to be approved, online and `idle`; it records a `ride_offers` row with `response = accepted`, frees the previous driver and tells both drivers and the rider.
- `admin:live` is emitted from the API node only while an admin socket is in the `admin` room; a second API replica would emit its own feed (fine for the pilot).

### D-041 — Still open after Phase 4
`GET /metrics` (§7.5), the daily retention job (§5) and the production Compose/backup files (§17) are Phase 5 items.

---

## Phase 5

### D-042 — `/metrics` is computed on scrape
SPEC §7.5 asks for "basic counters". Rather than an in-process metrics registry (which would differ between the API and worker processes), `GET /metrics` reads gauges from Postgres and Redis at scrape time: rides requested today by status, offers today by response, drivers online, active rides, pending online payments, open SOS alerts, process uptime. Authentication is `METRICS_TOKEN` (bearer header or `?token=`), constant-time compared; the route is 404 when the variable is unset. Scrape no more than once a minute.

### D-043 — Backup image and schedule
The `backup` service is a small Alpine image (`postgresql16-client` + `aws-cli`) built on the server from `infra/backup/`, not a stock image, so the prune-after-30-days logic and the restore script ship with the repo. It runs at 02:30 IST so the dump finishes before the 03:00 retention job. Backups go to the same R2 account as documents but may use a separate bucket (`BACKUP_BUCKET`).

### D-044 — Admin password change endpoint
SPEC §13 has a Settings page for the admin password but §7.4 lists no endpoint. `POST /admin/settings/password {current_password, new_password}` verifies the current password (failures count towards the 10-strike login lockout), requires at least 10 characters with a letter and a digit, refuses re-using the current password, revokes every other session of that admin, writes an audit entry and returns a fresh token pair so the current browser stays signed in.

### D-045 — Two kinds of refresh-token revocation
Rotation marks the used token `revoked_at`; presenting it again is **reuse** (SPEC §16) and revokes the whole family (401 `REFRESH_REUSED`). Administrative sign-outs — logout, account deletion, rider block, admin password change — now **delete** the user's refresh tokens instead. A token presented after one of those is simply 401 `REFRESH_INVALID`, and it can no longer take down sessions created afterwards (previously, a second browser refreshing after a password change would have signed the admin out everywhere, including the browser that changed it). Phase 1's D-016 ("logout revokes all refresh tokens") is amended accordingly.

---

## Apps

### D-046 — Flutter app architecture choices (Phase 2)
- **One token refresher per app.** The backend treats a concurrent rotation of the same refresh token as reuse and revokes the whole family, so the REST interceptor and the Socket.io client share a single-flight `TokenRefresher` (`apps/shared/lib/src/api/auth_interceptor.dart`).
- **The driver's background isolate never touches the network.** `flutter_background_service` runs only the geolocator stream and a 90 s watchdog and hands fixes to the UI isolate, which owns the socket, the tokens and the REST fallback batch. One socket, one token owner, no duplicate `driver:location` streams.
- **Maps and places have test seams.** `mapBuilderProvider` and `PlacesApi` are Riverpod providers with fakes, so widget tests never create platform views or call Google. Without a `GOOGLE_MAPS_API_KEY` the drop search degrades to a typed address plus "set location on map".
- **Riverpod 3 notes for tests:** providers pause without listeners (tests `listen` before awaiting `.future`), and failed `FutureProvider`s auto-retry unless `retry: null`.
- **Android manifest:** the plugin's foreground-service declaration is overridden with `tools:replace` to set `foregroundServiceType="location"` (Android 14). The Maps key is a Gradle `manifestPlaceholders` value read from `local.properties` or `MAPS_API_KEY` in the environment, empty by default so CI builds without a key.
- `driver:position` carries `ride_id` in addition to the SPEC §8 fields; the apps rely on it to ignore positions for other rides.

### D-047 — Per-trip earnings on the driver's history
SPEC §12 asks for an Earnings list "with fare, commission, net", but `GET /driver/rides` (§7.3) only returned the ride. Each item now also has `earning: {fare, commission, gst, net}` (null until there is a final fare), computed with the same fare-engine functions as settlements (`commissionOf` on the fare excluding GST, `gstOf`), so a week's list adds up to `GET /driver/earnings?period=week` and to the settlement. The fare configs are fetched once per page instead of adding a join to every ride query. `fare` is `final_fare`; a carried-over cancellation fee is not part of the driver's split (D-039).

### D-048 — Driver trip screen behaviour
- **Cancel reasons** are fixed choices sent as English text (`Vehicle breakdown`, `Rider not reachable`, `Rider no-show`, `Wrong pickup location`, or `Other: <note>`), since the API takes free text and the admin panel shows it as is. "Rider no-show" is only selectable 5 minutes after `arrived_at` (`NO_SHOW_WAIT_SECONDS` default); the server still decides whether it counts as a no-show.
- After the driver's own cancel, the screen says the ride went back to other drivers and ignores the `ride:status … reassigned` that follows, so it is not mislabelled as an admin reassignment.
- **PAID shows the rating step** (skip allowed) before Home; the earnings and history providers are refreshed when the driver leaves it.
- With an online payment the driver can still tap *Cash collected*: the server refuses with 409 `PAYMENT_PENDING` while a rider's online attempt is under 5 minutes old (D-037), and the message is shown.
- Arrived / Start / End send the latest fix from the online feed, or a one-off GPS read when there is none.

### D-049 — Android flavors and signing
`dev` and `prod` product flavors (SPEC §17.5). `dev` has the `.dev` package suffix and "(dev)" label so a staging build installs next to the store build, and it is the pubspec `default-flavor`, so `flutter run` needs no `--flavor`. Environment values stay `--dart-define`s (`API_BASE_URL`, `APP_ENV`, `GOOGLE_MAPS_API_KEY`, `SENTRY_DSN`) instead of per-flavor Dart entry points. Release signing reads `android/key.properties` or `KEYSTORE_PATH`/`KEYSTORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`. A partial set fails the build, and none at all falls back to the debug key for local `--release` runs. The CI release job refuses to build without the keystore secret, so a debug-signed bundle can never reach Play. First built on 2026-10-12 (JDK 21, Android SDK 36/37, NDK 28.2). Both `dev` release APKs are signed with a local test upload key that is kept outside the repo. The driver app additionally needs core-library desugaring (for `flutter_local_notifications`) and `compileSdk` 37 (for `permission_handler_android`). AGP 9.1 warns that 37 is above its recommended maximum, but builds; `targetSdk` stays 36.

### D-050 — Checking driving licences without a KYC provider
The pilot has no KYC (identity verification) contract and no registered business to sign one, and Parivahan's public lookup is captcha-protected, so it must not be scraped. Licences are therefore checked in two steps:
- **Offline format check** (`backend/src/modules/drivers/licence-number.ts`). It parses the standard 15-character Sarathi layout: state code, RTO, year of first issue, 7-digit serial. It warns on an unknown state code (pre-rename codes such as OR, UA and TS are accepted), RTO 00, a year in the future or before 1950, a licence issued before the driver turned 16, or a non-standard layout. Older licences can differ, so the check **only warns the admin and never refuses** a registration. The registration DTO keeps its loose `[A-Z0-9]{8,20}` rule.
- **Manual government lookup.** Drivers now give their date of birth (required; at least 18 by the IST date). The admin panel's *Check on Parivahan* button copies the number and opens Parivahan's "Know Your Driving Licence Status" page (`https://parivahan.gov.in/rcdlstatus/?pur_cd=101`), where the admin enters the date of birth and the captcha. The URL could not be fetched from outside India while building this; if Parivahan moves the page, change the constant in `admin/src/pages/drivers/LicenceCheck.tsx`.

Drivers registered before this change have no date of birth; the card says so, and asking them to re-register is not required for the pilot. Automated checks (a KYC provider's licence API, or DigiLocker) can replace the manual step once a business is registered.

### D-051 — Amazon S3 for documents during testing
SPEC §2 names Cloudflare R2. For the testing period the documents go to an Amazon S3 bucket the owner already has, so storage now supports both: `S3_ENDPOINT` set (R2 or another S3-compatible service, path-style URLs, `S3_REGION=auto`), or `S3_ENDPOINT` empty with `S3_REGION` set to the bucket's region (Amazon S3, virtual-hosted URLs). Storage stays disabled (503 `STORAGE_UNAVAILABLE`) when neither an endpoint nor a real region is set, because `auto` cannot sign for Amazon. The bucket blocks all public access, and the API's key needs only `s3:PutObject` and `s3:GetObject` on `bucket/*`; it uses presigned URLs only. No CORS rule is needed, because the app uploads natively and the admin panel opens documents through `<img>` and links. The dev bucket is in `ap-southeast-2` (Sydney); production should use `ap-south-1` (Mumbai), or R2 as planned, for latency and to keep Indian users' documents close to home.

### D-052 — Google Routes API instead of Directions
SPEC §9.2 names "Google Directions" as the routing fallback. Google has frozen the Directions API as "legacy", and new Cloud projects cannot enable it, so the fallback calls the Routes API (`POST routes.googleapis.com/directions/v2:computeRoutes`) with `routingPreference: TRAFFIC_AWARE`. That matches the old `duration_in_traffic`, which matters because fares include a per-minute component. The field mask asks only for `routes.distanceMeters,routes.duration`. The response omits zero-valued fields, so a missing distance is read as 0. Timeout, the 60 s Redis cache and the 503 `ROUTING_UNAVAILABLE` behaviour are unchanged. During testing, OSRM is not running and every estimate uses this path. One Google key (Maps SDK for Android, Places API (New), Routes API) serves the server and the apps for now. Before launch, split it into a server key (Routes only, restricted to the server's IP) and an app key (Maps SDK + Places, restricted to the apps' package names and SHA-1s), which needs the Android headers added to the Places client.

### D-053 — App design system
The first screens were bare Material defaults. The apps now share one design system in `ride_shared` (`AppTheme`, `AppColors`, `widgets/design.dart`) instead of per-screen styling:
- **One typeface, bundled**: Plus Jakarta Sans (SIL OFL, `apps/shared/fonts/`, licence alongside), five static weights so `FontWeight` maps exactly; no runtime font download.
- **Brand per app, shared everything else**: rider blue (`#2E5BFF`), driver green (`#0E9F6E`), so a driver who installs both never confuses them; saffron accent for fares, the trip OTP and earnings; success green for paid/approved/online. Colours come from `ColorScheme.fromSeed(fidelity)` with the neutrals overridden for a cleaner light surface, and a hand-tuned dark scheme.
- **Component themes over custom widgets**: radii 12/16/20/28, filled inputs, 54 px buttons, bordered cards without elevation, floating snackbars. The few reusable blocks (`SoftCard`, `SheetPanel`, `HeroPanel`, `StatusPill`, `RoutePoints`, `ActionCircle`, `InfoBanner`, `EmptyState`…) are plain widgets, not a third-party UI kit.
- **Tests unchanged in spirit**: every `Key` the widget tests use is kept; only assertions on presentation strings moved (e.g. "5.0 ★" → star icon + "5.0", "Not uploaded · Optional" → pill + "Optional"). `ActionCircle` and the rider card's call button are `IconButton`s so existing tests and screen readers see real buttons.
- **Visual verification without a device**: a screenshot harness per app renders the main screens to PNG in widget tests with the bundled font and Material icons loaded, plus a stylised fake map; it is skipped unless `RIDE_SHOTS` is set. Real Google Maps tiles still need a phone.

### D-054 — Admin panel through a second ngrok tunnel during testing
SPEC §17.4 deploys the panel to Cloudflare Pages, but during phone testing everything runs on one Mac behind an ngrok free tunnel. The free plan gives one HTTPS domain per account: a second endpoint on the same account is refused (`ERR_NGROK_334`) and paths on the domain are not allowed (`ERR_NGROK_9038`), so the panel gets its own tunnel from a second free account (ngrok's terms do not restrict this; checked 2026-10-14). Consequences:
- `ADMIN_ORIGIN` is a comma-separated list, so the tunnelled panel and the local dev server are both allowed by CORS. Single values keep working; production should list only the real panel origin.
- ngrok's free tier answers browser-looking requests with an interstitial page. Tested through the live tunnel: it intercepts `fetch` (even with `Accept: application/json`) but not WebSocket upgrades, and the `ngrok-skip-browser-warning` header bypasses it. The panel therefore sends that header on REST calls whenever its API base URL is an ngrok host; the `/rt` socket stays WebSocket-only and needs nothing.
- The tunnelled panel is the production build served by `vite preview` (port 4173, ngrok hostnames in `preview.allowedHosts`), built with `VITE_API_BASE_URL` set to the API tunnel. The local dev server on 5173 keeps talking to `localhost:3000`, so the panel's own polling does not use up the API tunnel's 20 000 requests a month.

Serving the panel from the API's own origin (no CORS, no second account) was considered and not done: helmet's default CSP on the API would block the panel's OpenStreetMap tiles, and it moves further from the planned static deployment.

### D-055 — Broadcast matching: several drivers see a request at once
SPEC §9.4 offers a ride to one driver at a time (nearest first, 20 s each, up to 3 offers). The owner wants drivers to see several requests and choose, as on bidding-style apps, so matching now works in **rounds**:
- Each round offers the ride to the nearest `OFFER_BATCH_SIZE` free drivers (default 5) at the same time. A driver may hold open offers from several rides; `driver:{id}:state = offered` is now informational (admin map colour) and never blocks another offer.
- The first accept wins under the existing ride row lock; everybody else in that round gets `ride:offer:expired` and their offer row is closed as **`withdrawn`** (new `offer_response` value). The winner's open offers from other rides are withdrawn too, which can end those rides' rounds early.
- A round ends when every driver has answered (the next round starts immediately) or when `OFFER_TIMEOUT_SECONDS` runs out (undecided offers are `timeout`). The next round asks drivers who were not offered this ride before. `MAX_OFFER_ROUNDS_PER_RIDE` (default 3) replaces `MAX_OFFERS_PER_RIDE`; the 2-minute deadline is unchanged.
- Going offline still answers open offers as `rejected`; a vanished driver's offers `timeout`; rider/admin cancel withdraws them.
- After a driver cancels an accepted ride, matching restarts excluding everyone who answered or cancelled it, but drivers who only lost a round (`withdrawn`) are asked again, otherwise a re-queued ride could run out of candidates.
- Redis: `ride:{id}:offers` (hash driver_id → expires_at, 25 s) and `driver:{id}:offers` (set, 10 min) replace `ride:{id}:offer` and `driver:{id}:offer`; `ride:{id}:offered_set` keeps its meaning. The `offer-timeout` job is per round (`offer_{ride}_{round}`) and ignores itself when a later attempt already exists, so "everyone answered" and "timed out" cannot double-start the next round.
- Events, payloads and REST/WS endpoints are unchanged; only their multiplicity differs. The driver app keeps a list of open offers, one card per ride with its own countdown, and the alert tone runs while any offer is open. e2e tests run with `OFFER_BATCH_SIZE=2` so rounds are observable with three drivers.
Trade-off: a popular pickup can make several drivers tap Accept for the same ride and lose; the app explains with the existing "no longer available" message and the other requests stay on screen. Queued "next ride while on a trip" was discussed and not built.

### D-056 — Vehicle classes: bike, auto, mini, sedan
SPEC §1 scopes the pilot to a single vehicle type and lists "multiple vehicle types" under Later. The owner asked for a choice with different prices now. The schema already carried `vehicle_type` on vehicles, fare configs and rides, and matching already filtered candidates by it, so the change is mostly surface:
- A fixed catalogue (`backend/src/common/vehicle-types.ts`, mirrored by `VehicleType` in `ride_shared`): `bike` (1 seat), `auto` (3), `mini` (4), `sedan` (4). Adding a class means adding it to both lists and seeding a fare config; there is no admin UI for new classes.
- **One route, one fare per class.** `POST /fare/estimate` computes every class that has an effective fare config and returns them as `options`; the top-level fields stay the sedan ones so older app builds keep working. `POST /rides` takes `vehicle_type` and checks that `fare_config_id` belongs to that class (`FARE_CONFIG_INVALID` otherwise). Drivers without a fare config for their class are never offered rides of it.
- **Per-class fare versions.** The seed creates a starting version for every class (admin-editable); the admin page shows one class at a time and `current_ids` carries the current version per class. Night multiplier, GST and commission remain per version, so they can differ by class.
- **Drivers declare a class** at registration (default sedan for older builds) and admins can correct it; the class is cached in Redis at go-online, as before, so a change applies the next time the driver goes online.
- Rider UI: the confirm screen lists the classes as selectable cards with icon, seats and fare range; the selected one is remembered in the booking draft for the session. Nothing else in the rider flow changes; the ride keeps its class for receipts and history.
Not done: per-class search radius or ETAs, class-specific cancellation rules beyond the fee already in each config, and a nearby-cars map that shows different icons per class (the API now returns `vehicle_type`, the map still draws one icon).

### D-057 — Aavagaman brand
The owner chose the name **Aavagaman** (आवागमन, "coming and going") with the tagline "Safar • Aapke Saath" and a brand board: a green "A" whose road climbs to a saffron location pin, app icons on charcoal/light/green tiles, a deep-green splash with road silhouettes, and ring-style loaders. Decisions:
- **The mark is code, not an image.** `AavagamanMark` is a `CustomPainter` (letter as a round-joined stroke with a mint→leaf gradient, a charcoal road with a dashed centre line, a saffron pin). It renders crisp at any size and in both apps without image assets; the same geometry is hand-written as `admin/public/logo.svg` for the panel and favicon. PNGs for Android are produced by a golden test (`RIDE_BRAND_OUT=<dir> flutter test --update-goldens test/branding` in `apps/shared`), then copied into `res/mipmap-*` (legacy icon, adaptive foreground, launch logo) and `docs/branding/`. Regenerate them whenever the painter changes.
- **Palette**: deep green `#0F3D2E` (rider primary, gradients), leaf `#15803D` (driver primary), fresh green `#22C55E` / mint `#4ADE80` (progress, dark-mode primary), saffron `#F59E0B` (accent: fares, OTP, pins), charcoal `#080F14` (dark surfaces, the driver's request screen). The two apps stay distinguishable by primary colour and name; the earlier blue rider theme (D-053) is gone.
- **Loaders**: `RouteLoader` (indeterminate arc with a pin head, "route progress" on the board) replaces the plain spinner on the splash and the fare estimate; `RingProgress` can draw a gradient sweep with a pin head and does so for "finding your driver". Material's default indicators remain elsewhere.
- **Splash scene is the owner's picture**: the brand board's India Gate sunset (`docs/branding/splash-india-gate-source.png`, shipped as a 275 KB JPEG in `ride_shared/assets`) is drawn full-bleed with `BoxFit.cover`, muted to 70 % saturation under a 34 % charcoal veil plus top/bottom scrims (`SplashLook`; the owner asked for the picture to sit back behind the mark, and this "muted + dim" option was chosen over a green tint, a blur and a near-night veil, see `docs/branding/splash-looks.png`); `SplashArt` composes it with the mark, wordmark, tagline and the Hindi line so it can be previewed in the branding test. A vector version (`IndiaGateScene`) was tried first and dropped on 2026-10-18 because the owner wanted the picture itself.
- **Native launch**: `launch_background.xml` is brand deep green with the mark, so there is no white flash before Flutter's first frame.
Not done: iOS icons (Phase 7), an animated logo, the Hindi wordmark (आवागमन) as an image, and store listing graphics beyond the 512 px icon.

### D-058 — Masked calling through the Aavagaman number
SPEC §16 reveals the other party's real number after ARRIVED and the apps open the phone dialer; "masked calling" was listed as Later. The owner wants calls the way the big ride apps do them: one company number, nobody sees anybody's phone. Decisions (2026-10-18):
- **Click-to-call bridge, not VoIP.** `POST /rides/:id/call` (rider) and `POST /driver/rides/:id/call` (driver) ask a cloud-telephony provider to ring the caller from the virtual number and, once answered, dial the other party and bridge them. Both phones show only the virtual number; the real numbers never leave the server. Ordinary phone calls, so it works on poor data and needs no in-app call screen. In-app VoIP (Agora/Twilio Voice) stays Later.
- **Provider behind an interface** (`CallProvider`): `exotel` (Connect API, India) is implemented; `stub` records calls without ringing anyone (dev, tests, demos); `none` keeps the SPEC §16 dialer behaviour. `CALL_PROVIDER` selects it.
- **Payload rule**: with a provider on, ride payloads for rider/driver carry `call_via` (the virtual number) while the ride is ACCEPTED/ARRIVED/STARTED and never `phone`; admins still get `phone`. With `none`, the old `phone`-after-ARRIVED rule applies. `phone_masked` is always present. The apps prefer the bridge when `call_via` is set, else the dialer when `phone` is set, else the button is locked.
- **Guard rails**: calls only while a driver is assigned and the trip has not ended (409 `RIDE_NOT_CALLABLE`); a caller may bridge once per `CALL_MIN_INTERVAL_SECONDS` per ride (429 `CALL_TOO_SOON`); calls are capped at `CALL_MAX_SECONDS`; recordings off.
- **Both processes mask**: the API and the worker both build ride payloads (`ride:status` events come from the worker), so the masking rule is applied in the global `RideCoreModule` from `CALL_PROVIDER`/`EXOTEL_CALLER_ID`, not in `CallsModule`.
- **Record**: every bridge is a `ride_calls` row (caller, callee, provider id, status, talk time). Exotel's status callback (`POST /webhooks/calls/exotel?token=CALL_STATUS_SECRET`, form-encoded) fills in the outcome; unknown ids are ignored. Admin ride detail lists the calls.
- **Cost and setup** are the owner's: an Exotel account with KYC, one ExoPhone (`EXOTEL_CALLER_ID`), API key/token and SID, and a public callback URL. Until then `CALL_PROVIDER=stub` lets the whole flow be exercised.
