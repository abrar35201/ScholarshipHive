# Original admin and Marketing Head access — role safety fix

- The original reserved `admin` account is now a regular `Admin` internally, **not** selectable `SuperAdmin`. Historical SuperAdmin enum value 4 remains for database backwards compatibility; old SuperAdmin accounts are converted to Admin at startup without resetting passwords.
- Original `admin` **cannot be deleted, disabled, unapproved, renamed or demoted** through the web or mobile APIs. It can change its own password and display name.
- Only this original `admin` account can explicitly **Grant / Revoke Admin Access** to a Marketing-department employee / Head of Marketing. Grant changes role to `Admin`; revoke changes role to `HeadOfMarketing` (department-scoped announcement authority, without admin dashboard access). No admin approval is required to announce from a head account.
- Existing Marketing employees accidentally created due to a mobile role-serialization bug can also be promoted from the Team page. Mobile mapping now sends correct numeric role values.
- Web: Team > Marketing user card > Grant Admin. After grant, Team > Admins & Auditors > Revoke Admin Access. Protected admin has no Delete button.
- Mobile: Admin > Team > Admins > marketing account > shield icon (Grant/Revoke). Original admin has no Delete icon.
- Promotion authorization is enforced server-side against the signed-in original admin user ID and database username, not just by hiding the UI.
- Existing SQLite database/users are preserved by this ZIP. Extract alongside, do not replace or delete your existing database without making a backup. For production use, review JWT revocation, audit logs, and application security.

## Run
Backend: `cd backend/ScholarshipHive.Server` then `dotnet run`
Flutter: `cd mobile`, `flutter pub get`, then `flutter run -d <deviceid> --dart-define=API_SERVER_URL=http://127.0.0.1:5080`

**Validation:** Static checks and archive validation completed; .NET and Flutter SDK are not installed in the packaging environment. Run `dotnet build` and `flutter analyze` locally before deploying.
