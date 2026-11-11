# ScholarshipHive: Targeted web/reception/password fixes

## Modified behavior

- Web department Heads use the existing **/TeamScope** page, with `/TeamScope/Add` POST and anti-forgery validation. The JSON endpoint `/api/team-scope/employees` remains Bearer/JWT-only and MUST return 401 when opened directly in an ordinary cookie-only browser tab. Do not remove JWT authorization to hide this expected error.
- Web TeamScope and Admin Create User forms now have password Show/Hide controls.
- Mobile department Add Employee, Apply for Leave, and Request Custom Shift now have password visibility toggles. The normal login screen already had this feature; it is unchanged.
- Visitor name, phone and optional email are validated server-side at `/api/reception/visitors`, and a browser-based registration form at `/Reception` uses the same server rules. Receptionist/Admin can register a visitor and check them out from that page.
- Mobile visitor registration does a matching preflight check, with helpful error messages. The server remains authoritative.
- The existing *Request leave/shift from anywhere* English copy is unchanged. No attendance, geofence, auto-checkout or employee router verification has been intentionally modified.

## Why repeated device resets can happen

`mobile/lib/services/device_id_service.dart` stores an installation-scoped random ID under `device_install_id` using SharedPreferences. Normal app restart preserves it, but uninstall/reinstall, clearing app data or replacing the device generates a new ID. The backend correctly refuses a different registered ID and requires explicit Admin reset. Do **not** disable device binding to hide this message. If an employee sees it on every ordinary app restart without data clearing, compare the saved SharedPreferences ID and backend HomeDeviceId; that needs live device investigation.

## Safety / testing

- Existing database is included only as a development snapshot. Back up and preserve the currently running `ScholarshipHive.dev.db` and configured connection string before switching ZIPs.
- .NET, Flutter and Android SDKs were not installed in the artifact-generation environment, so compilation, a successful browser POST and live on-device tests are NOT verified. Verify with `dotnet build`, `flutter analyze --no-pub`, `flutter run` and role-by-role tests.
- Security review is not a penetration test. Admin credentials, deployment secrets, HTTPS, access scopes and database backups must be reviewed before production.
