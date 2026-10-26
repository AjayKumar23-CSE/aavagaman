/** Public privacy policy (SPEC §20 Phase 5 "privacy policy pages"). Fill in the company details before release. */
export const PRIVACY_UPDATED = '2026-10-11';

export function privacyPolicyHtml(): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Privacy policy</title>
<style>
  body{max-width:720px;margin:0 auto;padding:24px 16px;font-family:system-ui,sans-serif;line-height:1.55;color:#111}
  h1{font-size:28px} h2{font-size:20px;margin-top:28px} table{border-collapse:collapse;width:100%} td,th{border:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top;font-size:14px}
  .muted{color:#555}
</style>
</head>
<body>
<h1>Privacy policy</h1>
<p class="muted">Last updated ${PRIVACY_UPDATED}. This policy covers the rider app, the driver app and the service behind them, operated by <strong>[Company name]</strong>, <strong>[registered address]</strong>, India ("we").</p>

<h2>What we collect</h2>
<table>
<tr><th>Data</th><th>Who</th><th>Why</th></tr>
<tr><td>Mobile number, name, optional email</td><td>Riders and drivers</td><td>Account login by one-time password, contact during a trip, receipts and support</td></tr>
<tr><td>Location</td><td>Riders while using the app; drivers continuously while online, including in the background</td><td>Pickup and drop, matching the nearest driver, live tracking, fare calculation and safety</td></tr>
<tr><td>Driving licence number, licence expiry and date of birth</td><td>Drivers</td><td>Checking the licence against the government (Parivahan) record before approval</td></tr>
<tr><td>Driver documents (driving licence, vehicle RC, insurance, permit, ID proof, selfie)</td><td>Drivers</td><td>Verifying that drivers and vehicles are allowed to operate; only the last four digits of an ID number are stored in our database, documents are stored privately and viewed by our verification team only</td></tr>
<tr><td>Trip details (route, times, fare, payment method, ratings)</td><td>Riders and drivers</td><td>Operating and settling trips, resolving disputes, accounting and tax</td></tr>
<tr><td>Payment confirmation</td><td>Riders paying online</td><td>Online payments are processed by Razorpay; we receive the order and payment identifiers and status, never card or UPI details</td></tr>
<tr><td>Device token, app version, crash and error reports</td><td>Riders and drivers</td><td>Push notifications and reliability; phone numbers and tokens are removed from error reports</td></tr>
</table>

<h2>Sharing</h2>
<p>During a trip the rider sees the driver's name, rating, vehicle and (after the driver arrives) phone number; the driver sees the rider's name, pickup, drop and (after arriving) phone number. A trip link the rider chooses to share shows the car's live position and the driver's name and vehicle, never the rider's details. We share data with service providers that help us operate: Razorpay (payments), MSG91 (SMS), Google (maps and push notifications), Cloudflare (hosting and storage), Sentry (error reports). We disclose data to authorities when the law requires it. We do not sell personal data.</p>

<h2>Retention</h2>
<p>Trip GPS traces are deleted after 30 days. One-time passwords expire within five minutes. Trip records are kept as long as accounting and tax rules require. When you delete your account the phone number, name and email are removed and the account can no longer be used; trip records are kept in anonymised form.</p>

<h2>Your choices</h2>
<ul>
<li>Delete your account from the app (riders: menu → Delete account; drivers: contact support).</li>
<li>Turn off location in your phone settings; the apps cannot book or run trips without it.</li>
<li>Contact us at <strong>[support email]</strong> or <strong>[support phone]</strong> for access, correction or deletion requests. Grievance officer: <strong>[name, email]</strong>.</li>
</ul>

<h2>Security</h2>
<p>All traffic is encrypted (HTTPS). Driver documents are stored in a private bucket and opened only through short-lived signed links. Access to the admin panel is restricted to our staff and every administrative action is logged.</p>

<h2>Changes</h2>
<p>We will post updates to this page and change the date above. Material changes will be announced in the apps.</p>
</body>
</html>`;
}
