# ScholarshipHive – Reception + Leave merge (development candidate)

This package is based on `samplescholarship.zip`. The original mobile theme, web CSS/layout, attendance, Wi-Fi BSSID verification, and geofencing source have not been replaced with code from the older project.

## Included changes

- New `Receptionist` role (role number 3); web admin and Flutter Team screen can create it. Self-registration under Create Account sends a **pending** approval request, visible in existing Team/Users approvals. Approval is mandatory before reception login.
- Flutter Reception screen for visitor registration, visitor log, and check-out, plus consent **draft records** and manual mark-signed. Admin web can view visitors and consent records.
- Employee/reception leave requests from the login/network-denied screen: username and password required, but **no Wi-Fi or GPS**. Check-in remains separate and still checks the approved office router for employees. Admin can approve/reject requests on web and Flutter; employees can check their own request status.
- Explicit **Admin login from anywhere** button (not an employee bypass) that validates Admin credentials and does not mark attendance.
- Existing geofencing source and saved locations preserved. Local Development config keeps `Attendance:RequireGeofence` false. Production currently still enforces geofence for employee attendance.
- Existing admin pending-user notification count covers reception registrations. Pending leaves are counted in the web notification indicator. Optional FCM notifications depend on Firebase configuration.

## Setup on Windows

After extracting the archive, open a terminal in `ScholarshipHive/backend/ScholarshipHive.Server`:

```powershell
dotnet restore
dotnet run
```

Your backend/web: http://localhost:5080

In a separate terminal in `ScholarshipHive/mobile`:

```powershell
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=API_SERVER_URL=http://localhost:5080
```

Android Pixel 7 over wireless ADB: connect the device first, then run:

```powershell
& "C:\Android\Sdk\platform-tools\adb.exe" reverse tcp:5080 tcp:5080
flutter devices
flutter run -d <YOUR_ACTUAL_DEVICE_ID> --dart-define=API_SERVER_URL=http://127.0.0.1:5080
```

Keep the backend process running. In an active `flutter run` terminal, press `r` for a Dart hot reload, `R` for hot restart. Backend C# edits require restarting `dotnet run`. After an initial install, code-only Flutter edits generally do not need another Gradle build.

## Validation and caveats

- SQLite schema CREATE statements were executed against SQLite to verify syntax; feature routes have not been exercised against a running server in this environment.
- The environment used to make the ZIP has no .NET/Flutter SDK, so **no dotnet build, flutter analyze or phone integration tests were possible here**. Run them locally before relying on this as a complete working release.
- A new PostgreSQL migration adds LeaveRequests, VisitorRecords and ReceptionConsents. **Back up your database before deploying/migrating.** The existing SQLite database is not erased: startup uses additive `CREATE TABLE IF NOT EXISTS` for new tables.
- Consent forms are stored as drafts and can be marked signed; sending email, PDF generation, real signatures and payment processing are **not** implemented and are not claimed to occur.
- Firebase push notification delivery is unavailable without a working Firebase service account and device tokens; existing web notification indicator/approval screens remain available.
- Existing `appsettings.Development.json` controls the local geofence override; do not use development configuration in production.
