# ScholarshipHive — Department RBAC & Announcements upgrade

Based on ScholarshipHive_Single_Login_Marketing_Processing_Full_Admin_Fix_2026-11-06.zip.

## Implemented source changes

- Removed the authenticated employee menu's **Request Custom Shift** entry. The outside-office application remains on the login screen.
- Centralized roles and announcement audiences. Owner/Admin roles retain organization-wide access; Country Head is read-only for system/role/network configuration; Head of Marketing uses Marketing + Interns; Head of Processing uses Processing; Head of Counselors uses Calling (Counselors); Receptionists can publish to Reception audience only.
- Added an authenticated DB-role check and restricted URL/API routes for department heads; stale cookies/JWTs after role changes are rejected. Department employee queries, attendance and reports validate the employee belongs to the requesting head's scope.
- Replaced department-head web landing with a scoped KPI dashboard (employees, presence, daily reports, pending leave/shift requests). Mobile department dashboard has the equivalent summary endpoint and cards. Marketing heads can add both Marketing and Intern employees within their scope.
- Announcement creates/edits/deletes now validate audience and creator on the server. Owner can delete any announcement; other authorized authors can delete only their own. MarketingAndInterns and Reception are announcement-only audience enums (5, 6); normal employee department dropdown excludes them. Employee announcements (including Interns) include notices from Owner and their authorized head.
- Existing announcements/history pages retained. Android/Flutter login popup remains, now checks all authenticated roles. Web portal added an authenticated announcement feed and acknowledgement popup using browser localStorage.
- Admin web notification bell counts pending **leave and custom shift requests**, and its link opens the new Action Center. Admin mobile notification bell polls the new pending-request endpoint every 30 seconds.
- Added a printable Italy consent record in the reception web portal. Printing/saving as PDF uses the browser's Print function (not a digitally signed PDF workflow).
- Country Head mobile overview uses read-only organization statistics, employee list, reception visitors and consent records, and announcement access. Sensitive write APIs are denied at middleware.
- Retained original files related to Wi-Fi/BSSID verification, geofences, attendance durations, device registration/reset, background workers, FCM and the database.

## IMPORTANT TEST LIMITATIONS

The ZIP was verified as an archive and modified source files received static structural checks. The environment here has **no dotnet/Flutter/Dart executable**, so **actual compilation, migrations, network tests, UI flows, and security penetration tests have not been completed**. This package is a development build candidate, **NOT independently verified production-ready**.

Popup acknowledgements are per-user/per-device (Flutter SharedPreferences) and per-user/per-browser (web localStorage); they do not sync across devices. Firebase pushes require valid Firebase service account configuration. Admin bell polling reflects database rows when the server is reachable. Reception printable document is not an e-signature.

## Recommended acceptance tests BEFORE using with real employee data

1. Backup the actual current SQLite/PostgreSQL DB and keep the old working project available.
2. Run `dotnet restore`, `dotnet build`, `dotnet run` from `ScholarshipHive/backend/ScholarshipHive.Server`.
3. Run `flutter pub get`, `flutter analyze --no-pub`, and `flutter run -d <DEVICE_ID> --dart-define=API_SERVER_URL=http://127.0.0.1:5080` from `ScholarshipHive/mobile` after `adb reverse tcp:5080 tcp:5080`.
4. Check the one login screen shift-request button and that authenticated employee popup menus no longer contain it.
5. Attempt `/Users`, `/NetworkSettings`, `/api/admin/users` with HeadOfProcessing, HeadOfMarketing, HeadOfCounselors tokens/cookies: expect forbidden, not cross-department records. Check scoped `/TeamScope` and `/api/team-scope` with Marketing + Interns vs Processing.
6. For Country Head, verify org read-only dashboard and denial of network changes, device resets, role creation, visitor creation and approvals.
7. Publish Owner all-employee notice and Head of Marketing Marketing+Interns notice; log in as an Intern and confirm both appear and acknowledge without deleting history. Verify Processing employee cannot see Marketing-specific announcements.
8. Submit pending leave and shift requests and verify the Owner web/mobile bell shows pending items. Test approval and that it disappears after decision.
9. Check Receptionist web sign-in, visitors, consent prefill, consent history and Print / Save PDF.
10. Check existing attendance network/geofence/device binding and auto-checkout against the saved backup, including on Android with battery restrictions.

## Confidentiality

Never include actual API keys, production DB secrets, or company data when sharing the project ZIP. Change publicly displayed testing passwords.
