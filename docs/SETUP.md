# Setting up Aavagaman on your machine

This guide takes you from a fresh clone to a working ride on your own computer: the backend, the admin panel, and the rider and driver apps on an Android emulator or phone. Plan for about an hour the first time, most of it downloads.

You will end up with:

| Part | Address | What it is |
|---|---|---|
| API | `http://localhost:3000` | NestJS backend, with API docs at `/docs` |
| Worker | (no address) | Background jobs: matching drivers, timeouts, payment checks |
| Database | `localhost:5432` | PostgreSQL with PostGIS |
| Redis | `localhost:6379` | Live driver positions, job queue |
| Routing | `localhost:5000` | OSRM, road distances and times for Delhi NCR |
| Admin panel | `http://localhost:5173` | Approve drivers, see rides, change fares |
| Apps | emulator or phone | Rider and driver apps (Flutter, Android) |

---

## 1. Install the tools

| Tool | Version | Why |
|---|---|---|
| Git | any recent | To clone the repository |
| Docker Desktop | any recent | Runs the database, Redis, routing, API and worker |
| Node.js | 22.12 or newer | For the admin panel, and for running the API outside Docker |
| Flutter | 3.44 or newer (stable) | For the two apps |
| Android Studio | any recent | Android SDK, an emulator, and a JDK (17 or newer) |

After installing Android Studio, open its SDK Manager and install Android SDK platforms 36 and 37, the build tools, and NDK 28.2. Then run:

```bash
flutter doctor
```

Fix anything it marks with a red cross before going on. Yellow warnings about iOS or Chrome can be ignored; the apps are Android first.

---

## 2. Clone the repository

```bash
git clone https://github.com/AjayKumar23-CSE/aavagaman.git
cd aavagaman
```

---

## 3. Start the backend

There are two ways. **Option A** needs only Docker and is the easiest. **Option B** runs the API directly with Node, which is better when you are changing backend code.

### Option A: everything in Docker (recommended)

```bash
docker compose -f infra/docker-compose.yml up --build
```

The first run takes a while: it downloads a map of Delhi and builds the routing data (5 to 15 minutes), then builds the API. Later runs start in seconds. Leave this terminal open.

When it settles, check it in a second terminal:

```bash
curl http://localhost:3000/health
```

You should see:

```json
{"status":"ok","db":true,"redis":true,"osrm":true}
```

The database is created and filled with starting data automatically: fare settings for Bike, Auto, Mini and Sedan, the Delhi NCR service area, and an admin account.

### Option B: API on your machine, services in Docker

```bash
docker compose -f infra/docker-compose.yml up -d postgres redis osrm
cd backend
cp .env.example .env
```

Open `backend/.env` and set at least these lines (the rest can stay as they are):

```
NODE_ENV=development
PORT=3000
API_BASE_URL=http://localhost:3000
ADMIN_ORIGIN=http://localhost:5173
DATABASE_URL=postgresql://ride:ride@localhost:5432/ride
REDIS_URL=redis://localhost:6379
OSRM_BASE_URL=http://localhost:5000
JWT_ACCESS_SECRET=<any long random text>
JWT_REFRESH_SECRET=<a different long random text>
OTP_PEPPER=<another random text>
OTP_DEV_BYPASS_CODE=123456
SEED_ADMIN_EMAIL=admin@ride.local
SEED_ADMIN_PASSWORD=<choose a password with letters and digits>
SEED_ADMIN_PHONE=+910000000000
```

A quick way to make random text: `openssl rand -hex 32`.

Then install, create the database tables, add the starting data, and start both processes:

```bash
npm install
npx prisma migrate deploy
npm run seed
npm run start:dev                     # the API, keep this terminal open
```

In a second terminal:

```bash
cd backend
npm run build && node dist/worker.js  # the worker, keep this open too
```

**Both must run.** Without the worker, ride requests are never sent to drivers.

---

## 4. Start the admin panel

```bash
cd admin
cp .env.example .env
npm install
npm run dev
```

Open `http://localhost:5173` and log in:

- Option A (Docker): `admin@ride.local` / `admin12345`
- Option B: the email and password you set in `backend/.env`

These are development logins. Never use them on a server other people can reach.

---

## 5. Get a Google Maps key

The apps need a Google Maps key to draw maps and to search for places.

1. Open [Google Cloud Console](https://console.cloud.google.com/), create a project, and turn on billing (Google's free monthly allowance covers development).
2. Under **APIs and Services**, enable **Maps SDK for Android** and **Places API**.
3. Under **Credentials**, create an API key. Restrict it to Android apps with the package names `com.rideplatform.rider.dev` and `com.rideplatform.driver.dev`, plus your debug signing fingerprint (the SHA-1 line printed by the command below).

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

(The debug keystore appears after Android Studio or Flutter has built any Android app once.)

Put the key in two files, which git ignores so it never gets committed:

```
apps/rider/android/local.properties     add a line:  MAPS_API_KEY=<your key>
apps/driver/android/local.properties    add a line:  MAPS_API_KEY=<your key>
```

(`local.properties` is created the first time Flutter builds the app; if it doesn't exist yet, create it.)

Without a key, the apps still work, but maps show as a grey area and place search falls back to "Set location on map".

---

## 6. Run the apps

Start an Android emulator from Android Studio (Device Manager), then in two terminals:

```bash
cd apps/rider
flutter pub get
flutter run --dart-define=GOOGLE_MAPS_API_KEY=<your key>
```

```bash
cd apps/driver
flutter pub get
flutter run --dart-define=GOOGLE_MAPS_API_KEY=<your key>
```

With two emulators open, Flutter asks which one to use for each app; give each app its own.

On the emulator the apps reach your computer's API at `10.0.2.2:3000` automatically. To use a **real phone** instead, connect it to the same Wi-Fi as your computer, find your computer's local IP address (for example `192.168.1.20`), and add it when running:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000 --dart-define=GOOGLE_MAPS_API_KEY=<your key>
```

**Emulator location:** an emulator starts somewhere in California. Set it to Delhi in the emulator's Extended Controls (the `…` button), under Location, or from a terminal:

```bash
adb emu geo fix 77.2167 28.6315    # Connaught Place
```

---

## 7. Try your first ride

1. **Rider app:** enter any 10-digit mobile number. The login code is always `123456` in development.
2. **Driver app:** log in with a different number, fill in the registration form (choose Sedan), and upload the six documents.
3. **Admin panel:** open **Drivers**, approve each document, then approve the driver.
4. **Driver app:** tap **Go online** and allow location "All the time".
5. **Rider app:** tap **Where to?**, pick a place, choose **Sedan**, and tap **Book ride**.
6. **Driver app:** accept the offer, tap **Arrived**, type the rider's 4-digit code, then **End trip** and **Cash collected**.

Both apps should step through the ride together. The rider and the driver must be within about 5 km of each other, so give both emulators the same location.

**Document uploads need file storage.** Driver documents go to an S3-compatible bucket. For local testing, create a free [Cloudflare R2](https://developers.cloudflare.com/r2/) bucket (or an Amazon S3 bucket), make an access key for it, and set `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY` in `backend/.env` (Option B) or in `infra/docker-compose.yml` (Option A). Without storage, step 2 stops at the uploads.

---

## 8. Optional services

Everything above works with no paid accounts. These add the remaining features; set each in `backend/.env` and restart the API and worker.

| Feature | Without it | To turn it on |
|---|---|---|
| Online payments | Riders can pay cash only | Razorpay **test** keys: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`. In test mode, pay with UPI ID `success@razorpay`. |
| Masked calls | Calls open the phone dialer after the driver arrives | Set `CALL_PROVIDER=stub` to try the flow without real calls, or `exotel` with an Exotel account (`EXOTEL_SID`, `EXOTEL_API_KEY`, `EXOTEL_API_TOKEN`, `EXOTEL_CALLER_ID`). See the README's "Masked calling" section. |
| Real SMS login codes | Only the development code `123456` works | MSG91: `MSG91_AUTH_KEY`, `MSG91_TEMPLATE_ID`, `MSG91_SENDER_ID`, and remove `OTP_DEV_BYPASS_CODE` |
| Push notifications | Drivers must keep the app open to see offers | A Firebase project: `FCM_SERVICE_ACCOUNT_JSON_BASE64`, plus `google-services.json` in each app |
| Google routing fallback | Routing uses only the local OSRM | `GOOGLE_MAPS_SERVER_KEY` with the Directions API enabled |
| Error reports | Errors only appear in logs | Sentry: `SENTRY_DSN` |

---

## 9. Run the tests

```bash
cd backend && npm test && npm run lint          # unit tests
cd admin && npm run lint && npm run typecheck
cd apps/shared && flutter test
cd apps/rider && flutter test
cd apps/driver && flutter test
```

The backend's end-to-end tests (`npm run test:e2e`) need a separate test database and Redis described in `backend/.env.test`; see the README.

---

## 10. When something goes wrong

| What you see | What to do |
|---|---|
| `port is already allocated` from Docker | Something else uses 3000, 5432, 6379 or 5000. Stop it, or change the left-hand number of that `ports:` line in `infra/docker-compose.yml`. |
| Health shows `"osrm":false` | The routing data is still building on the first run; wait and check again. If it keeps failing, set `GOOGLE_MAPS_SERVER_KEY` so the API can fall back to Google. |
| Booking says routing is unavailable | Same as above: OSRM is not ready and there is no Google fallback key. |
| The app says the server is unreachable | Is the API running? On a real phone, use your computer's local IP, the same Wi-Fi, and allow port 3000 through your firewall. |
| Grey map in the apps | The Maps key is missing from `local.properties`, Maps SDK for Android is not enabled, or the key's restrictions don't include the app's package name. |
| The rider always gets "no driver" | The worker isn't running, the driver isn't online, the driver's vehicle type differs from the one booked, or the two are more than about 5 km apart. |
| The driver can't upload documents | File storage isn't configured (see step 7). |
| The emulator shows the wrong place | Set its location to Delhi (see step 6). |

---

## Keep your keys out of git

`backend/.env`, `admin/.env` and the apps' `android/local.properties` are listed in `.gitignore`, so your keys stay on your machine. Keep it that way: never paste real keys into files that are committed, and use separate keys for anything other people can reach.
