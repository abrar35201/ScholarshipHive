# ScholarshipHive fingerprint-login update (2026-11-05)

## What changed
- Removed the **Lock App** menu/button and old locked-session route.
- Fingerprint enrollment is **per username, per Android installation**, not a device-wide boolean. Accounts must first sign in with a password, open Account Settings and enable Fingerprint Login with a successful Android biometric prompt.
- The server issues a protected biometric credential only to an authenticated, active and approved account. The credential is stored per username in `flutter_secure_storage`, not in plaintext preferences. Login checks the typed username, device installation ID, protected account ID and current username/password-hash version before a new JWT is issued.
- Full logout still clears the JWT but retains the account's enrolled biometric credential. Password changes, username changes, account deactivation and ticket expiry invalidate the server-side check. Tickets expire after 365 days; re-enrollment requires a password.
- Employee biometric login still requires approved office Wi-Fi/BSSID and the existing geofence policy (Development may temporarily set `Attendance:RequireGeofence` to false). Attendance is only created on that approved path. Admin, Auditor and Receptionist biometric logins never create attendance.
- Restricted the shared web/mobile dashboard weekly headcount and arrival curve to approved, active Employees, matching its other attendance cards.

## IMPORTANT limitations
- Android's local_auth API reports biometric success; it **cannot identify which individual enrolled finger** was used on a device. Account isolation is therefore by typed username plus server-verified account-specific credential, NOT by finger identity.
- Device binding uses the app's installation ID and OS secure storage, not a hardware-backed signing key attestation. A compromised or rooted phone and exfiltrated credential can defeat this client-side protection. For high-security production use, replace with Android Keystore private-key signing and server-side revocation tables.
- Disabling the toggle removes that device's local credential; changing the account password invalidates any previously issued ticket server-side. Full per-device server revocation requires a revocation registry not present here.
- These edits were checked for file/route/link consistency and ZIP archive integrity, **not compiled**: this environment does not have Flutter/Dart or the .NET SDK. Run the commands below and inspect errors before deploying.

## Windows run commands
In backend terminal (with the root folder as your working directory):

```powershell
cd backend\ScholarshipHive.Server
dotnet restore
dotnet build
dotnet run
```

In separate Flutter terminal:

```powershell
cd mobile
flutter pub get
flutter analyze --no-pub
& 'C:\Android\Sdk\platform-tools\adb.exe' reverse tcp:5080 tcp:5080
flutter run -d 33231FDH2002J7 --dart-define=API_SERVER_URL=http://127.0.0.1:5080
```

A backend C# code change always requires restarting `dotnet run`. A Dart-only change can often use Flutter hot reload `r` or restart `R`. If the installed app on this phone belongs to a previous project, back up app data and confirm you are in the intended development database before reinstalling.

## Test checklist
1. Admin password login -> Account Settings -> Fingerprint Login On (system prompt).
2. Logout -> enter `admin` -> fingerprint -> only Admin dashboard.
3. Login Hanan using password -> enroll fingerprint -> logout -> enter `hanan` -> fingerprint -> only Hanan dashboard.
4. Enter a username with no enrollment -> fingerprint -> must reject, password fallback available.
5. Rename/change password of an account -> its previous biometric ticket must be rejected.
6. Employee on unapproved BSSID -> fingerprint must reject attendance; on approved BSSID it may log attendance according to geofence mode.
7. Check web/mobile dashboard weekly-headcount and arrival curve against active approved employee attendance rows in the selected database.
