# ScholarshipHive — final source update (13 November 2026)

**Base:** User-uploaded `ScholarshipHive_Updated_Source_2026-11-12(1).zip`.
**Database:** PostgreSQL via EF Core + Npgsql; existing tables and data preserved by an additive migration.

## New behavior

1. Department Heads (Head of Counselors, Marketing, Processing): mobile employee card menu > **Reset phone device**. The server verifies a JWT and ensures that the employee belongs to that head's department. Country Head mobile directory also gets reset for ordinary employee accounts only. No head can reset an administrator's device using these routes.
2. Request For Custom Shift: show/hide password eye icon on Flutter login-screen request form. Authentication and shift processing are unchanged.
3. Calling employee forms: existing country-specific PDFs and saved submissions preserved. Head of Counselors can view all Calling employees' saved form records from **Calling Form Records** (web) or the document icon on their department mobile screen. The head can generate a new private link or revoke it. Generating a new link invalidates any previous link. The shared URL displays the **saved application fields** to anyone possessing the URL; it is NOT a signed or completed original PDF template. Mobile offers WhatsApp share and copy; web offers WhatsApp and copy.
4. Employee web access: existing cookie login for employees now opens **My Work / Daily Report**. Employees can submit/edit today's report or view recent report history in the web portal. Calling employees also retain country forms. For report submission a phone-created attendance row must already exist for today's Pakistan date. **Web login never generates check-in/out, device binding, heartbeat, Wi-Fi validation or work-time credit.** Existing phone check-in/out logic is unchanged.

## Data / link privacy

- New columns in PostgreSQL `CallingFormEntries`: nullable `PublicShareTokenHash` and `PublicShareCreatedAt` (migration `20261113000100_AddCallingFormPublicShares`). All existing rows remain unchanged.
- Share tokens are 256-bit random, saved as SHA-256 hashes. The public page sets no-index, no-referrer and no-store headers. Anyone with the current link can read applicant PII. Share only with authorized recipients.
- Public links are intentionally not searchable/listable, and the token is displayed only immediately after generation. Generate a new link if it is lost. Revocation removes access. They do not expire automatically.
- Default public URL uses the pre-existing Railway production domain. If using a different server domain, set `PUBLIC_BASE_URL=https://your-public-domain` on the backend.

## Verification completed here

- Extracted the exact uploaded ZIP and checked the 14 original consent PDFs.
- Ran 20 local static integration assertions (all passed), including routes/roles, PostgreSQL migration and public link controls.
- Byte-compared original and final backend `AuthController`, `AttendanceController`, `AttendanceDurationService`, plus mobile `attendance_check_worker.dart` and `office_geofence_service.dart`: unchanged.
- **Not possible in this environment:** `dotnet build`, `flutter analyze`, Android APK build, Flutter Web build, Railway PostgreSQL migration against your actual DB, browser interaction, live phone device installation, or real WhatsApp send. This is NOT a fully build-tested or production-verified release. Running source checks alone cannot guarantee no 404/runtime errors.**

## Before production deployment

1. Backup the production PostgreSQL database; the application automatically runs EF Core migrations at startup.
2. Extract the ZIP, then execute `PRE_DEPLOY_CHECKS.ps1` on a machine with .NET 10 and Flutter installed, or run the commands inside it manually. **Do not skip the build if production uptime matters.**
3. Review `git status`, commit all new `.cs`, `.cshtml`, `.dart` and EF migration files, plus original PDF templates, to your existing GitHub `main` branch. Do not commit passwords or keystores.
4. Confirm Railway backend deploy logs show migration applied successfully; smoke test login, Calling employee creation, head link generation, anonymous link, revoked link, and phone-only attendance.

## Important boundaries

- No changes were made to the existing phone check-in/out, geofence or work-hour engine.
- PDF agreements remain original PDFs; public links show the *entered application details*, not an electronically filled PDF or legally signed contract.
- Only one public share link can be active per saved draft at any time.
