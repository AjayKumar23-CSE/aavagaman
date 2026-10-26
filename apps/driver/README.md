# Driver app

Flutter driver app (SPEC §12). Phase 1 covers login and onboarding; Phase 2 adds going
online with background location, the ride-offer popup and the "Navigate to pickup" screen.
Arrived / OTP / trip / payment / earnings screens arrive in Phase 3/4.

**Flow:** Splash (session plus `GET /driver/me`) → Phone → OTP → Registration → Documents →
Pending approval → Home (Online/Offline switch) → Offer popup → Navigate to pickup. After login,
the router gates every screen on the driver profile (see `gateFor` in `lib/src/router.dart`):

| Driver state | Screen |
|---|---|
| `suspended` | Account paused, contact support |
| not `registered`, or `rejected` | Registration (prefilled; shows the reviewer note) |
| a mandatory document never uploaded | Documents |
| `pending` | Pending approval: status, reviewer note, rejected documents with notes |
| `approved` | Home; an open offer owns the screen; a current ride opens the trip screen |

## Phase 2 behaviour

- **Online switch (Home).** Switching on: permissions (fine location, background location
  "All the time" on Android 10+, notifications) → one GPS fix → `POST /driver/online` → the
  foreground service starts with the persistent notification "You are online". Status text
  shows offline / online / "Reconnecting…" (socket down) and the server's reason when the switch
  is refused (`403 NOT_ELIGIBLE`, `409 ON_TRIP`). The switch is disabled during a trip. The
  one-time battery-optimisation guide opens after the first successful go-online (also in the
  drawer) with notes for Xiaomi/Redmi/POCO, Vivo, OPPO/OnePlus, Realme and Samsung and deep links
  to the battery and app settings. Today's earnings is a placeholder card until Phase 4.
- **Background location.** `flutter_background_service` runs `geolocator` in a location
  foreground service (`lib/src/presence/background_entry.dart`). The service isolate only streams
  fixes to the UI isolate; the UI isolate owns the socket and every REST call, so the refresh
  token has one owner (the backend revokes all tokens on a concurrent rotation).
  `PresenceController` sends `driver:location` every 4 s (2 s during a trip), drops fixes with
  accuracy > 100 m, queues up to 10 fixes and flushes them through `POST /driver/location` while
  the socket is down, and re-sends `POST /driver/online` on `409 DRIVER_OFFLINE` or when the socket
  reconnects while the switch is on. If the UI isolate disappears (app killed) the service stops
  itself after 90 s; the server has already marked the driver offline after 15 s.
- **Offer popup.** `ride:offer` opens a full-screen page: pickup address, distance to pickup,
  fare range, drop address, a countdown ring to `expires_at`, Accept / Reject. A looping tone
  (`assets/sounds/offer.wav`, alarm stream) and vibration run until accept, reject, expiry or
  `ride:offer:expired`. Accept goes over the socket (`driver:offer:accept`) with a REST fallback
  when the socket is down or the acknowledgement is lost; `409 OFFER_NOT_VALID` / `DRIVER_BUSY`
  return to Home with the message.
- **Navigate to pickup.** Rider name, masked phone (full phone and Call from ARRIVED), pickup and
  drop, fare range, *Navigate* (`google.navigation:q=lat,lng`, falls back to a Google Maps URL).
  Arrived / Start trip / End trip are shown disabled until Phase 3. A reassigned or cancelled ride
  shows why and returns Home.
- **Push.** The FCM background handler shows a full-screen-intent notification on channel
  `rides` (custom sound) for `type: ride_offer`; foreground `ride_offer` / `ride_status` messages
  reconnect the socket / refresh the ride. Everything is behind try/catch until Firebase is
  configured.

Shared code lives in [`../shared`](../shared) (`package:ride_shared`). All strings are in
`lib/l10n/app_en.arb`.

## Android setup

`android/app/src/main/AndroidManifest.xml` declares `ACCESS_FINE_LOCATION`,
`ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`,
`POST_NOTIFICATIONS`, `VIBRATE`, `USE_FULL_SCREEN_INTENT`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`,
the background service with `foregroundServiceType="location"`, intent queries for navigation
and the dialer, and the Maps SDK key placeholder. The offer sound is also bundled as the raw
resource `res/raw/offer.wav` for the notification channel.

**Maps SDK key.** `com.google.android.geo.API_KEY` is filled from the Gradle placeholder
`MAPS_API_KEY`: put `MAPS_API_KEY=<key>` in `android/local.properties` (git-ignored) or export
`MAPS_API_KEY` before building. An empty value still builds (the driver UI has no map yet).

## Run

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

The app takes the same `--dart-define`s as the rider app: `API_BASE_URL`, `GOOGLE_MAPS_API_KEY`
(unused by the driver UI for now), `SENTRY_DSN` and `APP_ENV`. The dev OTP bypass code is
`123456`. Document uploads need the backend's S3/R2 settings to point at object storage the
phone can reach.

## Test

```sh
flutter analyze --fatal-infos && flutter test
```

Tests use real `GET /driver/me`, ride and WebSocket payloads from `test/fixtures` (captured from
the running backend), a fake Socket.io socket (`package:ride_shared/testing.dart`), and fakes for
the location feed, permissions and the alert sound.

## Not done yet

- **Firebase / push:** not configured yet; setup is the same as in the rider app's README.
- **Phase 3:** Arrived / OTP / Start / End, cancel with reason, SOS, trip history, earnings.
- **Flavors** and **release signing:** as in the rider app's README.
- **PDF upload:** the API accepts PDFs, but the app only uploads photos.
- **Lost image-picker results:** if Android kills the app while the camera is open, the photo
  is lost (`ImagePicker.retrieveLostData` isn't handled).
- **Device-only behaviour not verifiable here:** the foreground service, background location on
  Android 10+/14, the full-screen notification on a locked phone, OEM battery managers, the alarm
  stream volume and the navigation intent need a real Android phone.
