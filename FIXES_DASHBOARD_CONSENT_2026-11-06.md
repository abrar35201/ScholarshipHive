# 2026-11-06 – Reception consent + dashboard refresh fix

## Fixed
- Reception Consent records now link to GET /Reception/Consents (cookie-authenticated MVC page) instead of /api/reception/consents (JWT-only API).
- New consent draft links to GET /Reception/CreateConsent and posts to POST /Reception/CreateConsent with anti-forgery token. Visitor-linked draft prefill retained.
- Dashboard keeps database-driven metrics and adds 20-second no-cache refresh fallback in addition to real-time SignalR updates; refreshes when browser tab returns to foreground.
- Chart heading now accurately describes hourly **new** check-ins (not cumulative); hourly graph is responsive and skips overlapping hour labels on small screens.
- Previous processing admin access, receptionist login, mobile app and announcement popup preserved.

## Test
1. In backend folder: `dotnet restore`, `dotnet build`, `dotnet run`.
2. Web login as admin/receptionist, open `/Reception`, click Consent records, New consent draft, create and save a draft.
3. Open `/` as admin, create an employee check-in from phone, and watch dashboard for ~20 seconds. Data will only change when attendance records change.
4. If old browser page persists, use Ctrl+Shift+R once after installing this version.

## Limitations
- This environment lacks .NET and Flutter SDKs: no live compilation or browser/mobile testing performed.
- Keep existing `ScholarshipHive.dev.db` backed up; ZIP's SQLite file may be older than your active data.
