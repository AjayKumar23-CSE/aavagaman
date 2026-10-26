# Rider app

Flutter rider app (SPEC §11). Phase 1 covers login and profile; Phase 2 adds the map, booking,
Finding and Driver-assigned screens. Trip, payment and rating screens arrive in Phase 3/4.

**Screens:** Splash (restores the session with `GET /me`) → Phone → OTP (resend after 30 s) →
Name (first login only) → Home (map) → Set drop (search) → Set location on map → Confirm →
Finding driver → Driver assigned / en route → status screen. The drawer has Profile,
Help & support, Privacy policy, Log out and Delete account.

| Screen | What it does |
|---|---|
| Home | Google map centred on the GPS fix (permission denied or location off → Connaught Place plus a prompt with *Allow location* / *Open settings*). Nearby idle cars from `GET /drivers/nearby` every 10 s, drawn as car icons rotated by heading, no identity. "Where to?" sets the pickup to the current position and opens the search. |
| Set drop | Places Autocomplete (Google Places API New, NCR rectangle, India only, session token), 400 ms debounce, 3-character minimum, recent places, *Set location on map*. Without a Places key the screen still works: type an address and pin it on the map. |
| Set location on map | Drag the map under a pin, optionally name the place, confirm (used for the drop and for changing the pickup). |
| Confirm | Pickup/drop on the map, `POST /fare/estimate` fare range + distance/time, payment selector (Cash default / Pay online), out-of-area notice when `in_service_area.drop` is false, *Book ride* (`POST /rides`). `FARE_CONFIG_INVALID` re-estimates; `ACTIVE_RIDE_EXISTS` jumps to the existing ride. |
| Finding | 2-minute countdown ring from `requested_at`, Cancel (`POST /rides/:id/cancel`), handles `ride:no_driver`. |
| Assigned / en route | Driver card (name, rating, vehicle, plate), live car marker from `driver:position`, ETA from `eta_s`, trip OTP large, Call (dialer intent; enabled only once the server reveals the phone from ARRIVED), Cancel (fee warning after 2 min; Phase 2 backend answers 409 after accept and the message is shown), Share trip and SOS present but disabled with a "Coming soon" tooltip. |
| Status | STARTED / COMPLETED / PAID / CANCELLED / NO_DRIVER as a plain card; *Back to home* / *Done* dismisses an ended ride. |

**Live updates.** `RealtimeClient` (shared) keeps one Socket.io connection to `/rt` while logged
in. `activeRideProvider` loads `GET /rides/active` on launch and on every resume, re-sends
`rider:subscribe`, merges `ride:status` events and quietly re-fetches the ride for timestamps.
A "Reconnecting…" strip appears on ride screens while the socket is down.

Shared code (API client, models, realtime client, Places, session, login screens, widgets)
lives in [`../shared`](../shared) (`package:ride_shared`). All strings are in `lib/l10n/app_en.arb`.

## Run

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
            --dart-define=GOOGLE_MAPS_API_KEY=<key>   # Places search; optional
```

| `--dart-define` | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:3000` | Backend origin (`/v1` REST, `/rt` Socket.io) |
| `GOOGLE_MAPS_API_KEY` | empty (search off) | Google Places API (New) key for autocomplete + details |
| `SENTRY_DSN` | empty (Sentry off) | Crash reporting; phone and token fields are scrubbed |
| `APP_ENV` | `dev` | Environment reported to Sentry |

**Maps SDK key.** The Android Maps SDK reads its key from the manifest
(`com.google.android.geo.API_KEY`), filled from the Gradle placeholder `MAPS_API_KEY`. Put
`MAPS_API_KEY=<key>` in `android/local.properties` (git-ignored) or export `MAPS_API_KEY` in the
environment before building. The same Google Cloud key can serve the Maps SDK and Places; an
empty value still builds (the map shows no tiles).

Against the dev backend, the OTP bypass code is `123456`. Debug builds allow cleartext HTTP
(`android/app/src/debug/AndroidManifest.xml`). Release builds are HTTPS only.

## Test

```sh
flutter analyze --fatal-infos && flutter test
```

Tests use real API and WebSocket payloads from `test/fixtures` (captured from the running
backend), a fake Socket.io socket from `package:ride_shared/testing.dart`, and a placeholder
map builder (`mapBuilderProvider`) so no platform view is needed.

## Not done yet

- **Firebase / push:** there's no Firebase project yet. To enable push, add
  `android/app/google-services.json` and apply the `com.google.gms.google-services` Gradle
  plugin (see the TODO in `android/app/build.gradle.kts`). Until then `Firebase.initializeApp`
  fails quietly and the app runs without an FCM token. Once configured, the token goes to
  `device.fcm_token` at login and to `POST /me/fcm-token` on every start and on token refresh.
  `ride_status` data messages are not yet handled in a background handler; the socket re-sync on
  resume covers it for now.
- **Phase 3 screens:** trip in progress (route line), fare & payment, rating, Share trip
  (`share_token` link) and SOS are stubbed (disabled buttons / plain status card).
- **Recent places** live in memory for the session only; **pickup address** is the literal
  "Current location" (no reverse geocoding yet).
- **Flavors:** the `dev`/`prod` flavors from SPEC §17.5 aren't set up yet. Adding them would
  break the CI release job, which builds without `--flavor`. For now, use `--dart-define`.
- **Release signing:** builds use debug keys until the Phase 5 CI secrets are wired up.
