# ScholarshipHive merged version — local testing (Windows PowerShell)

## Important

This is a development source bundle. No Flutter or .NET compiler was available in the packaging environment. **Run the checks below before using it for real employee data.** Preserve your old working ZIP.

The ZIP contains an existing *development SQLite database* copied from the supplied project. It is a snapshot; keep it private. New tables are created on startup for the local SQLite setup. Use a database backup before any real PostgreSQL migration.

## Backend / Web (Terminal 1)

Extract the ZIP, open PowerShell inside its `ScholarshipHive` subfolder, then:

```powershell
cd backend\ScholarshipHive.Server
dotnet restore
dotnet build
# Optional, one time for the provided existing developer DB:
$env:Bootstrap__PromoteAdminToSuperAdmin = "true"
# Optional, if you have a Google AI Studio key:
$env:Gemini__ApiKey = "YOUR_PERSONAL_GOOGLE_AI_STUDIO_KEY"
dotnet run
```

Web: http://localhost:5080 (do not open 0.0.0.0:5080).

Never leave the `Bootstrap__PromoteAdminToSuperAdmin` flag enabled in a production deployment: it is intended for explicit bootstrapping of a trusted existing local `admin` account. Fresh databases seed a SuperAdmin automatically. Change seeded development passwords before any external deployment.

## Flutter Android / Pixel 7 (Terminal 2)

```powershell
cd mobile
flutter pub get
flutter analyze --no-pub
& "C:\Android\Sdk\platform-tools\adb.exe" devices
& "C:\Android\Sdk\platform-tools\adb.exe" reverse tcp:5080 tcp:5080
flutter run -d 33231FDH2002J7 --dart-define=API_SERVER_URL=http://127.0.0.1:5080
```

Replace the device ID with the one shown by `flutter devices` if different. Use **r** for hot reload and **R** for hot restart only when `flutter run` is still active. First install of a new ZIP requires a full build. USB Debugging authorization must be enabled.

## Flutter Chrome (optional)

```powershell
cd mobile
flutter run -d chrome --web-port=3000 --dart-define=API_SERVER_URL=http://localhost:5080
```

## What to test first

1. Admin web -> Reception -> visitor -> Create consent draft prefilled with visitor details; consent records must open a web page (not raw `/api/reception/consents`).
2. Receptionist can register (pending approval) and then log in after admin approval.
3. Admin Web & Android -> Announcements -> all employees; department heads only scoped notices; edit and delete appropriately.
4. Employee -> Request Custom Shift outside Wi-Fi -> admin Web/Mobile approve -> new shift hours effective.
5. First password login of employee binds phone; logging in second employee on same phone fails; reset via admin Web/Mobile before replacement.
6. Employees on approved router can check-in; away/nonapproved router blocks attendance; GPS optional only for local Development according to existing config.
7. Manual checkout earlier than 9 hours should show actual credited minutes; open sessions close after 10 elapsed hours; more than 9 hours must never be credited on one business day.
8. AI Assistant: set key in backend terminal, ask read-only factual question, inspect answer and API logs. Google quota/models differ per project.
9. Verify the Today, Analytics, Hours, and Attendance widgets agree for one actual checkin and checkout; historical data may contain earlier stale sessions requiring reconciliation.

## Caveats

* Announcements are persisted in the database. Remote device push notifications require valid Firebase ServiceAccountJson and FCM configuration; otherwise in-app fetching works but external pushes don't.
* Google AI Studio offers free-tier model access subject to eligibility/rate limits. A real private key must be created by the user; none is bundled. Free-tier requests may be used by Google for model improvement — obtain workplace consent before uploading sensitive staff data.
* Device binding uses a device-install ID, not a tamper-proof hardware identity; protect the phone and enforce HTTPS for deployed environments.
* 9-hour credited and 10-hour auto-checkout logic was changed at the backend; exact network-away detection depends on Android heartbeat delivery and connectivity. No mobile/production integration test was executed here.
* Migrations for PostgreSQL must be tested on a *backup* before production deployment. Changing existing roles may need one-time superadmin bootstrap.
