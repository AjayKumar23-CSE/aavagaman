# Play Store release notes (SPEC §17.5, §20 Phase 5)

Two apps, both Android-first: **Rider** (`com.rideplatform.rider`) and **Driver** (`com.rideplatform.driver`). Track: internal testing → closed testing (at least 12 testers for 14 days on a new personal developer account) → production.

## Before the first upload

- Signing keys: generate one upload keystore per app (`keytool -genkeypair -v -keystore rider-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`), keep them with the client, and give CI the base64 of each plus the passwords as secrets (`RIDER_KEYSTORE_BASE64`, `RIDER_KEYSTORE_PASSWORD`, `RIDER_KEY_ALIAS`, `RIDER_KEY_PASSWORD`, same for `DRIVER_*`). Enrol in Play App Signing.
- Version code comes from the CI run number (`--build-number`); the version name is the tag (`rider-v1.0.0`).
- CI builds the `prod` flavor (`--flavor prod`) with the repo variables `API_BASE_URL`, `GOOGLE_MAPS_API_KEY` and `SENTRY_DSN`; it refuses to build if the keystore secret is missing. The `dev` flavor (`com.rideplatform.rider.dev` / `.driver.dev`) is for staging testers and is not uploaded to Play.
- Firebase project with both Android apps added; `google-services.json` placed in `apps/<app>/android/app/` and the Google Services Gradle plugin enabled (both are TODOs in the Gradle files).
- Google Maps Platform key restricted to the package names and SHA-1s (add the `.dev` packages if staging builds need maps); Places API (New) enabled.
- Firebase: register the `.dev` package names as well if push is needed on staging builds.
- Privacy policy URL: `https://api.<domain>/v1/legal/privacy` (served by the API; also link it from the apps' Privacy screen).

## Listing text

**Rider — short description**: Book a sedan across Delhi NCR in two taps: upfront fare range, live tracking, trip OTP and SOS.

**Rider — full description**: Aavagaman is a simple cab-booking app for Delhi, Gurugram, Faridabad, Noida, Greater Noida and Ghaziabad. See the fare range before you book, watch your driver arrive live, share your trip with family, and pay by cash or UPI/card. Every trip starts with a 4-digit OTP so only you can begin it. SOS calls 112 and alerts our team.

**Driver — short description**: Drive with Aavagaman in Delhi NCR: go online, accept nearby requests, navigate, and track your earnings.

**Driver — full description**: For verified partner drivers. Go online when you want to drive, receive requests from riders near you, navigate with Google Maps, start each trip with the rider's OTP, collect cash or receive online payments, and see today's and this week's earnings. Weekly settlements are prepared automatically.

## Data safety form

| Data | Rider app | Driver app | Purpose | Shared? |
|---|---|---|---|---|
| Phone number | Collected (account) | Collected (account) | Login (OTP), contact during a trip | Driver sees rider's number only after arriving; rider sees driver's number after arrival |
| Name | Collected | Collected | Shown to the other party | Yes, to the other party of the trip |
| Email (optional) | Collected | — | Receipts, support | No |
| Date of birth | — | Collected | Licence verification on Parivahan | No |
| Precise location | Collected while in use | Collected **in the background** while online (foreground service) | Pickup, matching, live tracking, fare | Rider's pickup/drop shared with the assigned driver; driver position shared with the rider and admins |
| Photos / documents | — | Collected (licence, RC, insurance, permit, ID proof, selfie) | Driver verification | No; stored privately, viewed by admins only |
| Payment info | Handled by Razorpay | — | Online payment | Processed by Razorpay; the app never sees card/UPI details |
| App activity, crash logs | Collected | Collected | Diagnostics (Sentry, Crashlytics) | No; phone numbers and tokens are scrubbed |
| Device ID (FCM token) | Collected | Collected | Push notifications | No |

Data is encrypted in transit (HTTPS/WSS). Users can request deletion from the app (Rider: Delete account; Driver: via support) — the account is anonymised and trips are kept for accounting (SPEC §16). Trip GPS tracks are deleted after 30 days.

## Background location declaration (driver app)

- Feature: receiving ride requests and sharing live position with the rider while the driver is online, including when the app is in the background or the screen is off.
- Why foreground service with location type: continuous location is required to match drivers to nearby riders and to show the rider where their car is.
- In-app prominent disclosure before requesting background location: "To receive ride requests and share your live location with riders while you are online, Aavagaman collects location data even when the app is closed or not in use."
- Demo video: show the Online switch, the persistent "You are online" notification, the phone locked, then a request popup arriving.

## Testing checklist before each production push (SPEC §19)

- Device matrix: one Xiaomi/Redmi, one Samsung, one Vivo/Oppo/Realme; Android 10, 12 and 14.
- Driver app killed mid-trip → reopen → trip resumes with the correct state.
- Airplane mode for 60 s mid-trip → "Reconnecting…" → recovers, positions resume, no duplicate offers.
- Phone reboot while online → driver is marked offline by the server (heartbeat) and the app shows the switch off on reopen.
- Rider: payment flow with a Razorpay test UPI; share link opens in a browser; SOS dials 112 and the admin panel shows the alert.
