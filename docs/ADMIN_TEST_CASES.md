# BlinCab admin panel — test cases

For the test team checking the admin panel before the pilot. Work through the sections in order; section D (driver document verification) is the priority and needs the driver app on a phone at the same time.

**Panel:** `https://uncooked-slacking-dipped.ngrok-free.dev/admin/`. The first visit in each browser shows an ngrok warning page; click **Visit Site**. Ask Ajay for the admin login. Never share it in a group chat.

**How to record results:** put **Pass**, **Fail** or **Blocked** in the Result column. For every Fail, note the time, the driver/rider/ride involved and take a screenshot.

**Priority:** P1 must pass before the pilot, P2 should pass, P3 nice to have.

## Before you start

- [ ] The driver app (BlinCab Driver, build 13 or later) is installed on a phone with a number that has **never** registered before. This is your "new driver".
- [ ] The rider app (build 12 or later) is installed on a second phone.
- [ ] Have sample files ready on the driver phone: a clear photo (JPG), a PNG, a PDF, and one deliberately blurry photo.
- [ ] Open the admin panel on a laptop in Chrome. Keep a second browser (or private window) handy for the session tests.

---

## A. Login and session

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| A1 | P1 | Valid login | Open the panel, enter the admin email and password, sign in | Dashboard opens; header shows the BlinCab logo and name | |
| A2 | P1 | Wrong password | Enter the right email with a wrong password | Error message; stays on login; no detail on which field was wrong | |
| A3 | P2 | Unknown email | Enter an email that is not an admin | Same error as A2 | |
| A4 | P2 | Empty fields | Click sign in with both fields empty | Browser asks for the fields; no request sent | |
| A5 | P1 | Rider/driver cannot log in | Try the panel with a rider or driver account (if they have an email) | Refused | |
| A6 | P1 | Protected pages need login | Sign out, then paste a deep link such as `/admin/drivers` | Login page opens; after signing in you land on the Drivers page (not `/admin/admin/…`, not a 404) | |
| A7 | P2 | Sign out | Click sign out | Back to login; the browser Back button does not show data | |
| A8 | P2 | Page refresh keeps you signed in | Sign in, open any page, press F5 | Same page reloads, still signed in | |
| A9 | P3 | Session expiry | Leave the panel idle for a long time (or overnight), then click around | Sent back to login with the page you were on remembered | |

## B. Dashboard

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| B1 | P1 | Tiles load | Open Dashboard | Rides today, Completed, Cancelled, Online drivers, Revenue (paid), Pending drivers, Open SOS are shown | |
| B2 | P1 | Pending drivers count | Note the count; register a new driver with all documents (see D1–D3) | Count goes up by one within about 30 seconds without refreshing | |
| B3 | P2 | Online drivers count | Take a driver online, then offline | Count follows within about 30 seconds | |
| B4 | P2 | Rides by status | Book a ride from the rider app | It appears in "Rides by status (today)"; with no rides the page says "No rides requested yet today." | |
| B5 | P2 | Revenue | Complete and pay one ride | Revenue (paid) goes up by the fare | |
| B6 | P2 | Open SOS | Press SOS in an app | Open SOS tile goes up | |

## C. Drivers list

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| C1 | P1 | Status tabs | Click All, Pending, Approved, Rejected, Suspended | List filters correctly; the URL keeps the filter on refresh | |
| C2 | P1 | Search | Search by name, by phone, by registration number | Matching drivers only; "No drivers match these filters." when none | |
| C3 | P2 | Pending documents count | Look at a driver with uploads awaiting review | The row shows how many documents are pending | |
| C4 | P2 | Check licence badge | Register a driver with an odd licence number (e.g. wrong state code or future year) | Row carries the **Check licence** badge | |
| C5 | P2 | Blocked/inactive user | A driver whose account is not active | Name shows the account status in red | |
| C6 | P3 | Pagination | With more drivers than one page | Next/Previous work; page number kept in the URL | |
| C7 | P2 | Open driver | Click a row | Driver detail opens | |

## D. Driver document verification (priority)

Use the new driver phone together with the admin panel. Seven document types exist. Six are **mandatory**: Driving licence, RC, Insurance, Permit, ID proof, Selfie. **Fitness certificate** is optional. Driving licence, Insurance, Permit and Fitness need an expiry date.

### D-a. Upload from the driver app

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| D1 | P1 | Register a new driver | On the driver app: sign up with OTP, fill profile, licence number, date of birth and vehicle | Driver appears in admin under **Pending** | |
| D2 | P1 | Upload all mandatory documents | Upload JPG/PNG/PDF files for all six mandatory types with future expiry dates | Each upload succeeds; app shows them as under review | |
| D3 | P1 | Documents visible in admin | Open the driver in admin | Each card shows the file preview, "Uploaded … IST", the expiry date and a **Pending** badge; amber banner "Awaiting review:" lists them | |
| D4 | P1 | Missing mandatory document | Leave one mandatory type (e.g. Permit) not uploaded | Card says "Not uploaded — required"; red banner "Missing mandatory documents: Permit" | |
| D5 | P2 | Optional fitness | Leave Fitness empty | Card says "Optional" / "Not uploaded"; no red banner for it | |
| D6 | P1 | Expiry required | Try to upload Insurance without an expiry date | App refuses with a message that an expiry date is needed | |
| D7 | P1 | Already expired document | Try to upload Permit with an expiry date in the past | App refuses: "This document has already expired" | |
| D8 | P1 | ID proof last 4 digits | Upload ID proof without the last 4 digits | App refuses: "Enter the last 4 digits of your ID"; with digits, admin Profile shows "•••• 1234" | |
| D9 | P2 | File types | Upload a JPG, a PNG and a PDF | All three accepted and previewable in admin | |
| D10 | P2 | Unsupported file | Try a file type other than JPG/PNG/PDF (e.g. HEIC or a video) | Refused with a clear message | |
| D11 | P3 | Large file | Upload a very large photo (10 MB+) | Either uploads or shows a clear size message; no app crash | |

### D-b. Reviewing documents in admin

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| D12 | P1 | Open full size | Click a document preview | File opens full size in a new tab (images and PDFs) | |
| D13 | P1 | Approve a document | Click **Approve** on Driving licence | Badge turns **Approved**; Approve button disappears; Reject stays | |
| D14 | P1 | Reject needs a reason | Click **Reject** on the blurry document and submit an empty reason | Dialog says "A reason is required." | |
| D15 | P1 | Reject with note | Reject with "Photo is blurry — upload again" | Badge **Rejected**; note shown on the card; red banner "Rejected, awaiting re-upload: …" | |
| D16 | P1 | Driver sees rejection | Check the driver app | The rejected document shows the admin's note and asks for a new upload | |
| D17 | P1 | Re-upload after rejection | Driver uploads a new file for the rejected type | Admin card shows the new upload as **Pending**; "1 older upload" expands to show the rejected one with its note and a View file link | |
| D18 | P2 | Only the latest upload is reviewable | Open the older upload in one tab; in another tab the driver re-uploads; try to approve the old one | Refused: "A newer upload of this document exists; review that one" | |
| D19 | P2 | Change your mind | Reject an approved document, then approve it again | Both work; each is logged in Audit | |
| D20 | P2 | Signed links expire | Leave a driver page open for 5+ minutes, then click a preview | Either refreshes automatically or shows a retry; **Refresh links** button restores the previews | |
| D21 | P1 | Licence check card | Look at the Licence check card | Shows licence number, date of birth (DD-MM-YYYY) and either green "standard format" or an amber list of warnings | |
| D22 | P2 | Parivahan copy | Click **Check on Parivahan** and the DOB Copy button | Licence number and DOB are copied; Parivahan page opens | |
| D23 | P2 | Selfie | Look at the selfie on the driver header | Selfie shows; if missing, "No selfie" | |

### D-c. Approving the driver

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| D24 | P1 | Approve blocked by pending docs | With at least one mandatory doc still pending, click **Approve driver** | Refused: "Approve these documents first: …" listing the missing ones | |
| D25 | P1 | Approve blocked by rejected doc | With one mandatory doc rejected | Same refusal, listing that document | |
| D26 | P1 | Fitness not needed | Approve all six mandatory docs, leave Fitness missing, click **Approve driver** | Driver approved; badge **Approved**; "Approved (IST)" filled in | |
| D27 | P1 | Driver app updates | Watch the driver app right after D26 | Within seconds the app shows approved and the driver can go online; a push notification arrives | |
| D28 | P1 | Go online | Driver taps go online | Driver goes online; appears on the Live map and in "Online drivers" | |
| D29 | P1 | Unapproved driver cannot go online | Try going online with a pending driver | App refuses and explains documents are under review | |
| D30 | P2 | Document rejected after approval | Reject an approved mandatory doc of an approved driver, then driver tries to go online | Driver cannot go online until it is re-uploaded and approved | |
| D31 | P2 | Expired after approval | Edit the vehicle (section F) so Insurance expiry is yesterday, or use a driver whose doc has just expired | Card shows red "Expires …" with **Expired** badge and red banner "Expired: Insurance"; driver cannot go online | |

## E. Driver account actions

Each action asks for confirmation, and Reject/Suspend need a reason.

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| E1 | P1 | Reject a pending driver | **Reject driver** with a reason | Status **Rejected**; driver app shows the reason and sends them back to registration | |
| E2 | P1 | Approve a rejected driver | After the driver fixes things, **Approve driver** | Works once all mandatory docs are approved | |
| E3 | P1 | Suspend | On an approved driver, **Suspend** with a reason | Status **Suspended**; driver is taken offline and cannot go online; push shows the reason | |
| E4 | P1 | Reinstate | On the suspended driver, **Reinstate** | Status **Approved**; "Cancellations today" reset to 0; driver can go online | |
| E5 | P2 | Buttons match status | Look at each status | Pending: Approve, Reject. Approved: Reject, Suspend. Rejected: Approve. Suspended: Reinstate | |
| E6 | P2 | Auto-suspend | Driver cancels three accepted rides in one day | Driver suspended automatically; alert on Live map; reinstate works (E4) | |
| E7 | P2 | Cancel the dialog | Open Suspend and press Cancel | Nothing changes | |

## F. Vehicle edit

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| F1 | P2 | Edit vehicle | Open **Edit** on the Vehicle card, change colour and model, save | Values update on the page and in the driver app | |
| F2 | P2 | Field limits | Enter a registration number longer than 13 characters, or make/model over 40 | Input stops or shows an error | |
| F3 | P2 | Expiry dates | Change Insurance/Permit/Fitness expiry | Saved; past dates show in red as "(expired)" | |
| F4 | P3 | Vehicle type and fuel | Change type (Bike/Auto/Mini/Sedan) and fuel | Saved; driver gets ride requests only for the new class | |

## G. Riders

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| G1 | P2 | Search | Search by name, phone, email | Matching riders shown | |
| G2 | P1 | Block | **Block** a test rider with a reason | Toast "Rider blocked"; rider app signs out within seconds; OTP login refused | |
| G3 | P1 | Unblock | **Unblock** (note optional) | Toast "Rider unblocked"; rider can sign in again; ride history still there | |
| G4 | P3 | Real phone numbers | Look at rider rows | Admin sees full phone numbers | |

## H. Rides

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| H1 | P1 | List and filters | Filter by status, date range (from/to), driver id, rider id | Correct rides; times in IST | |
| H2 | P1 | Ride detail | Open a completed ride | Pickup/drop, fare (estimated and final), distance/time, timeline with every status change and who did it, GPS track on the map | |
| H3 | P2 | Offers | Open a ride that was offered to several drivers | Offers table shows who was offered, when, and their response or timeout | |
| H4 | P2 | Payment card | Open a paid online ride | Method, amount, gateway order/payment ids, paid time | |
| H5 | P2 | Calls card | Rider calls the driver during a ride | Calls card lists who called, outcome and talk time; numbers are not shown to rider/driver apps | |
| H6 | P1 | Cancel ride | On an active ride, **Cancel** with a reason | Ride CANCELLED, no fee to rider; driver freed; both apps update | |
| H7 | P1 | Reassign | On an ACCEPTED or ARRIVED ride, **Reassign** to another online idle driver | Both drivers' apps update; rider sees the new car. With no idle driver: "No other idle drivers are online right now." | |
| H8 | P2 | Adjust fare | On a completed ride, **Adjust fare** with a reason | New fare shown; timeline says "Fare adjusted ₹X → ₹Y"; unpaid online payment uses new amount | |
| H9 | P2 | Mark cash | On a COMPLETED (unpaid) ride, **Mark cash** | Ride becomes PAID with method cash | |
| H10 | P2 | Actions match status | Check which buttons show for each status | Cancel only before completion; Reassign only ACCEPTED/ARRIVED; Mark cash only COMPLETED | |
| H11 | P3 | Rider cancellation fee | Rider cancels after the free window | Ride shows "Cancelled by rider … fee ₹X" | |

## I. Live map

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| I1 | P1 | Drivers on map | Take two drivers online | Both pins show; green = free | |
| I2 | P2 | Colours | Send a ride request; accept it | Pin turns amber while offered, blue on trip | |
| I3 | P2 | Active rides list | During a ride | Ride listed with driver, rider and pickup | |
| I4 | P2 | Connection label | Watch the status label; switch off Wi-Fi briefly | "Live" → "Reconnecting — polling" → "Live" | |
| I5 | P3 | Driver goes offline | Driver goes offline | Pin disappears or turns stale | |

## J. SOS

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| J1 | P1 | SOS appears | Press SOS in the rider app during a ride (tell the team first; the app may dial 112, cancel the call) | Alert listed with time, ride link and location | |
| J2 | P1 | Acknowledge | Click **Acknowledge** | Toast "SOS acknowledged"; alert leaves the open list; Dashboard Open SOS count drops | |
| J3 | P2 | Driver SOS | Press SOS from the driver app | Same as J1 | |

## K. Fare config

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| K1 | P2 | Tabs per class | Click Bike, Auto, Mini, Sedan | Each shows its own version history; current one marked | |
| K2 | P1 | New version | Create a new version with all fields, effective now | Saved; new estimates in the rider app use it | |
| K3 | P2 | Preview calculator | Enter a distance and duration | Shows estimate range and the final-fare cap; "Fill in every field to preview." when incomplete | |
| K4 | P2 | Future effective time | Set "Effective from" to later today | Current version keeps applying until that time | |
| K5 | P2 | Invalid values | Negative numbers, commission over 100% | Refused with a message | |
| K6 | P3 | Existing rides keep their tariff | Request a ride, then publish a new version | That ride keeps the quoted tariff | |

## L. Service areas

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| L1 | P2 | View areas | Open Service areas | Polygons on the map; list on the side | |
| L2 | P2 | Draw and save | Draw a new area, name it (e.g. "Test zone"), save | Toast confirms; appears in the list | |
| L3 | P1 | Deactivate | Deactivate an area | Rider cannot book a pickup inside it | |
| L4 | P2 | Drop outside | Book a drop outside all areas | Allowed; rider app shows a flag | |
| L5 | P3 | GeoJSON import | Import a valid file, then a broken file | Valid imports; broken shows "Import failed: …" | |

## M. Settlements

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| M1 | P2 | Weekly list | Open Settlements, pick a past week | One row per driver: rides, gross, commission, cash, online, amount payable | |
| M2 | P2 | Generate | Generate statements for a past week | Created; the current or a future week cannot be generated | |
| M3 | P2 | Mark settled | **Mark settled** with a payment reference (e.g. NEFT UTR) | Toast "Marked settled"; status settled; reference stored | |
| M4 | P3 | Settled is frozen | Generate the same week again after settling | Settled row unchanged | |

## N. Reports

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| N1 | P2 | Date range | Pick a range | Daily rows and Total: requested, completed, cancelled, paid, gross, commission, GST, cash, online | |
| N2 | P2 | Charts | Same page | Rides per day and revenue cash vs online charts match the table | |
| N3 | P3 | CSV | Download CSV and open in Excel/Sheets | Same numbers as the screen | |

## O. Audit log

Check after the sections above; every admin action should be here.

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| O1 | P1 | Document actions logged | Filter entity "driver_document" | Each approve/reject from section D with actor, time, before/after and the note | |
| O2 | P1 | Driver actions logged | Filter entity "driver" | Approve, reject, suspend, reinstate with reasons | |
| O3 | P2 | Other actions | Look for ride cancel/reassign/fare adjust, rider block, SOS acknowledge, tariff and service area changes, settlements | All present | |
| O4 | P3 | Filters | Filter by actor id, entity id | Correct rows | |

## P. General

| ID | P | Test | Steps | Expected | Result |
|---|---|---|---|---|---|
| P1 | P2 | Settings hidden | Look at the side menu | No Settings entry | |
| P2 | P2 | Branding | Login page, header, browser tab | BlinCab name and vehicles logo; no old name anywhere | |
| P3 | P2 | Deep link refresh | Open a driver detail, press F5 | Same page reloads (no 404) | |
| P4 | P3 | Small screen | Open the panel on a phone browser | Usable; menus and tables scroll | |
| P5 | P3 | Two admins at once | Two people review the same driver | Second action shows a clear message if the state already changed; no crash | |
| P6 | P3 | Server down | Ask Ajay to stop the API briefly | Panel shows an error banner with retry, not a blank page | |

---

## End-to-end smoke run (30 minutes)

If time is short, run just these in order: A1 → D1 → D2 → D3 → D14 → D15 → D16 → D17 → D24 → D13 (all six) → D26 → D27 → D28 → I1 → E3 → E4 → O1 → O2.
