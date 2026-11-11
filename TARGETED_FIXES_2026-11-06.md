# ScholarshipHive targeted fixes — 2026-11-06

Base: ScholarshipHive_RBAC_DepartmentHeads_Announcements_Notifications_2026-11-06.zip

## Changed
- Removed "Marketing + Interns" from new announcement audience dropdowns (web and Flutter). Marketing and Interns are separate audience choices. Historical combined notices are still readable.
- Head of Marketing can explicitly select **Marketing** or **Interns**. No cross-department free-text targeting; server validates audience role.
- Announcement API/web displays the author's real saved account role alongside full name. This reflects the author's **current** role, not a historical frozen publication role.
- Shift Requests moved from admin account popup into the admin-side navigation drawer (Flutter).
- Shift changes by admin on web or mobile now write PRIVATE per-user notices. Employees see their notice in Announcements history and on next login in the unread popup. If FCM is configured a real push is also attempted. If FCM is disabled there is no guaranteed background push/instant alert.
- Added user-specific JWT-only `/api/user-notices`; it can fetch **only the signed-in user's** notices. A new `UserNotices` database table is created non-destructively for SQLite and via migration for PostgreSQL.
- Navigation guard: drawer transitions close the drawer before changing the underlying tab tree; the post-login device-switch notice now closes using the dialog's own context. Other red-screen sources remain possible.
- Preserved existing login, router lock, geofencing, attendance, device binding, reports, consent and FCM implementations.
- Fixed existing Razor CSS `@media` escaping in `PrintConsent.cshtml` (was known to break `dotnet build`).

## Required validation on Windows (NOT compiled here)
1. In `ScholarshipHive/backend/ScholarshipHive.Server` run `dotnet restore; dotnet build; dotnet run`.
2. In `ScholarshipHive/mobile` run `flutter pub get; flutter analyze --no-pub` then run on phone.
3. Log in with Owner, Head of Marketing and regular Employee. Verify Marketing vs Interns audience is separately enforced by API and unread popup.
4. Save individual and bulk shifts in both web and Flutter, verify only affected users see their personal shift notice and database records persist.
5. Open admin menu and drawer; verify no extra Shift Requests entry in account popup and the drawer entry is accessible.
6. Test troublesome back-navigation sequence; a complete widget stack trace is needed to diagnose any remaining `_dependents.isEmpty` assertion.
7. Backup `ScholarshipHive.dev.db` or PostgreSQL before switching. Do not overwrite the active database with the packaged development sample.

Notes: Archive/source consistency is checked, but full .NET, Flutter, Android and browser execution are not available here; no bug-free guarantee.
