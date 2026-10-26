# Aavagaman test builds — notes for testers

Thanks for trying Aavagaman. These are early Android test builds that talk to a development
server, so expect rough edges, and please tell us what you see.

## Install

1. Open the APK you were sent (`aavagaman-rider-…apk` or `aavagaman-driver-…apk`) on your phone.
2. Android will ask to allow installs from this source; allow it once. The app is signed with a
   test key, so Play Protect may show a warning; choose "Install anyway".
3. On first start allow **Location** ("while using the app"; drivers also **all the time**) and
   **Notifications**.

Both apps can be installed on the same phone.

## Signing in

Enter your mobile number. The server is in test mode, so the OTP is always **123456**.
Drivers: register once (name, vehicle type, vehicle number), then an admin approves you.

## What to try

- **Rider**: the map should open on your location. Pick a destination, choose Bike / Auto / Mini /
  Sedan, book, watch the driver approach, share the trip link, pay by cash or online (test mode).
- **Driver**: go online, accept a request, tap Arrived at the pickup, enter the rider's 4-digit
  OTP to start, end the trip, collect cash.
- **Calling**: tap Call on either side once a driver is assigned. Your phone rings first from the
  Aavagaman number; answer it and the other person is connected. Neither of you sees the other's
  number. During the trial only phones we have registered can be called, so tell us your number
  if calls fail.
- **SOS** dials 112 for real. Please do not test it.

## Known limits of the test build

- The server runs on a development machine; if it is off, the app shows "server unreachable".
- Location on the map can take 10–15 seconds indoors.
- Online payment runs in Razorpay **test mode**; no money moves. In the payment sheet choose UPI
  and enter `success@razorpay` to simulate a successful payment (`failure@razorpay` simulates a
  failed one). Cards and netbanking also show Razorpay's test options.

Report problems with a screenshot and the time it happened.
