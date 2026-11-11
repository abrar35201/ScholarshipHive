# ScholarshipHive — Setup & Run Guide

## What's inside
- `backend/ScholarshipHive.Server` — ASP.NET Core (.NET 10) app. Contains both:
  - The **Admin panel** (Razor views, cookie login) at `/`
  - The **REST API** used by the mobile app at `/api/...` (including a JSON admin API at `/api/admin/...` for the mobile Admin panel)
- `mobile/` — Flutter app (Android-first). Employees get the check-in/report/logout experience; Admins get a full admin panel right there in the app.
- Database: PostgreSQL, hosted on Railway (see below) — not on anyone's personal laptop.

## 1. The backend is hosted in the cloud (Railway) — always on
The backend and its database run on Railway, not on your laptop. **This means the whole system works 24/7 regardless of whether your laptop is on, asleep, or even in the room** — the same as any normal website.

- Public URL: `https://scholarshiphive-backend-production-b17d.up.railway.app`
- Project dashboard: `https://railway.com/project/360d30df-f853-454c-b103-202dc250b424`
- Database: a managed Postgres instance in the same Railway project (not the local Postgres that used to run on this laptop during early development — that one is no longer used by the live app).

**Redeploying after a code change:**
```
cd backend/ScholarshipHive.Server
railway up
```
This builds the Dockerfile and pushes a new deployment — takes about 20-30 seconds. Config (database connection string, JWT signing key) lives in Railway's environment variables for this service, not in the source code.

**Local development** (optional, for testing before deploying):
```
cd backend/ScholarshipHive.Server
dotnet run
```
This still works exactly as before, listening on `http://<your-LAN-IP>:5080`, using your own local Postgres — useful for trying things out before pushing to `railway up`, but it's not what the phones or the public web login actually talk to anymore.

## 2. Approving routers — the easy way
The mobile app only allows login/registration/check-in when the phone is connected to a Wi-Fi network whose **BSSID** (the router's radio MAC address) is on the approved list. There's no IP/subnet requirement and no dependency on where the backend or the admin happens to be — purely "is this BSSID approved."

**You generally don't need to do anything manually.** When any device (an employee's phone, anywhere) tries to check in from a network that isn't approved yet, the attempt is captured automatically as a **Pending Network** — with its real BSSID already read from that device. Open the Admin panel (web: **Network Settings**, or mobile: **Network** tab) and you'll see it listed with how many times it's been tried — tap **Approve** and it's live immediately.

Other ways to add a router, from the **mobile** Network tab (nothing to type, ever):
- **Add Current Network** — one tap adds whatever network the admin's own phone is connected to right now.
- **Scan Nearby** — shows every Wi-Fi network the phone can currently detect (not just the one it's connected to, e.g. both a 2.4GHz and 5GHz band from the same router), check off any number and add them all at once.

On the **web** panel, Network Settings → Add Router is a manual name + BSSID form — this is a fallback only (browsers have no way to read Wi-Fi info, unlike phones), for when you already have a BSSID from another source. Normally you won't need it; Pending Networks or the mobile app's auto-detect cover everything.

Multiple routers can be active at once (different offices, different employees' homes, etc.) — each independently lets devices on that network check in.

## 3. Point the mobile app at your backend
Already done — `mobile/lib/core/api_config.dart` points at the permanent Railway URL. The phone just needs **any internet connection** (Wi-Fi or mobile data) to reach the backend; it no longer needs to be on the same network as anything. (Being on an *approved* Wi-Fi network is still required for check-in — that's the router/BSSID system above, which is a separate, deliberate restriction, not a technical limitation.)

If the backend is ever redeployed to a different URL, update `serverUrl` in that file and rebuild the app.

## 4. Run the Flutter app
```
cd mobile
flutter run
```
On first run, Android will ask for **Location permission** — required so the app can read the connected Wi-Fi's BSSID/name (used to check whether the network is approved, not to reach the backend). It also asks for the Nearby Wi-Fi Devices permission on Android 13+, and Notification permission for the daily welcome notification.

## 5. How the app behaves

**Getting an account**
- New employees tap **"New here? Create an account"** on the login screen — this only works while on an approved network. They pick their own username/password.
- New accounts are **pending** until an Admin approves them (Users → Pending Approval, on web or mobile). They can't log in until then.
- Admins can also create accounts directly — those are approved immediately, no waiting.
- A user can change their own username/password any time from **Account Settings** in the app (needs their current password to confirm).

**The web login (on `/`) is Admin-only.** An Employee account entering correct credentials there gets a clear "this portal is for administrators only, use the mobile app" message instead of being let in. The mobile app is different: the same login works for both roles there — an Admin lands on the full admin experience (Dashboard/Users/Attendance/Reports/Network), an Employee lands on their own check-in/report screen.

**Logging in — once, not every day**
- First time (or after an explicit logout), the user signs in with username + password.
- After that, the app remembers them (a securely-stored, long-lived token, refreshed every time the app opens). As long as they're on an approved network, opening the app takes them straight in — no password prompt — and checks them in for the day automatically.
- If they explicitly log out, they'll need to sign in with their password again next time.

**Attendance & reports (server-enforced, not just in the app)**
- **First app-open/login of the calendar day** marks that day's attendance (check-in time recorded, shown persistently on the Home screen — not just a one-time toast). Later opens the same day don't create a second record or move the check-in time.
- **The daily report is entirely optional** — submitting it is the employee's choice, never required to log out. At most one report per day is accepted; it can include free text, an attached file (any type — PDF, image, document, whatever), or both.
- The report screen's **"Attach a file"** button accepts any file type — the original file is stored as-is, and an Admin can open/download it from the Reports view (web or mobile) to view exactly what was submitted.
- **Check-out time is recorded whenever the user logs out**, updating again if they log out a second time later the same day — logout always succeeds immediately, no conditions attached.
- Every login, check-in, and logout is recorded in a permanent history log — not just the daily summary.
- All times display in 12-hour format with AM/PM, everywhere (web and mobile).

**Live updates — no manual refresh, anywhere**
- The web admin panel and every tab of the mobile admin panel update **instantly** the moment anything changes (an employee checks in, a report comes in, a router gets approved) — no reload button, no waiting. This runs over a live connection (SignalR); a 60-second background check acts as a safety net in case a live update is ever missed.

**Automatic Wi-Fi detection: welcome notification + auto check-in/checkout**
- While the app is running (foreground, or backgrounded/minimized but not fully closed), it watches the Wi-Fi connection roughly every 45 seconds.
- The **first time** it sees an approved network on a given day, it shows a local notification — *"Welcome to ScholarshipHive — you're connected, tap to check in for today"* — and checks the user in automatically at that moment.
- When it detects the device has left an approved network, it makes a best-effort call to record a checkout.
- **Important limitation:** none of this runs if the app has been fully closed/swiped away from recent apps — Android stops all app code in that case. It resumes working as soon as the app is reopened. A version that keeps working even when fully closed would need a native Android foreground service — ask if you want that built out.

**The mobile Admin panel** (shown automatically instead of the Employee screen when an Admin logs in)
- **Dashboard** — total users, checked-in count, today's reports, active routers, pending counts.
- **Users** — approve pending registrations, add accounts, tap any user for a full detail view.
- **Attendance** — check-in/check-out per user per day.
- **Reports** — submitted report content and attached files, tap to view or open.
- **Network** — approve/dismiss Pending Networks, view/toggle/delete approved routers, add one via auto-detect or a nearby-networks scan.

**Full audit history per user** — tap any user in the Users tab to open their detail screen: profile fields, attendance history, submitted reports, and a complete **Login/Check-in/Logout event log** with exact timestamps.

**Security**
- Router check is purely BSSID-based — independent of the Wi-Fi password, so changing a router's password never breaks access.
- 5 failed password attempts locks the account for 15 minutes. An admin can unlock instantly by re-saving the account under Users → Edit.
- Passwords are always hashed, never stored in plain text.
- The database connection string and JWT signing key live only in Railway's environment variables, never in source code.

## Managing employees
Web Admin panel → **Users**: approve/reject self-registered accounts, or add/edit/delete directly (Role = Employee or Admin). Employee accounts can only ever use the *mobile* app — the web panel rejects their login outright. **Attendance** shows check-in/check-out per user per day; **Reports** shows submitted report content and attachments, filterable by user/date; **Network Settings** shows approved routers and any Pending Networks awaiting approval.
