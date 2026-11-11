# ScholarshipHive: Targeted Web, Department Removal, Auditor UX & Authorization Patch

## Changes

1. Web sidebar uses independently scrollable navigation with a fixed Logout footer, including at 90% zoom and shorter browser heights.
2. Existing colored-emoji sidebar icons for Audit Activity, Leave Requests, Reception, Announcements and Shift Requests replaced with neutral, currentColor outline SVG icons to match existing links.
3. Department Heads can select **Remove employee** from their own team (web and Flutter). This is a **soft removal**: the user's `IsActive` is set false and FCM token removed; the removed employee is hidden from the active department roster and can no longer authenticate; historic attendance/reports retained. An Owner/Admin can access the archived account. The action is strictly scoped by current role and department on the server. No hard delete and no cascading history loss.
4. Auditor login opens a dedicated read-only **Audit Activity** page. Filters: actor, action, entity type, from/to UTC. Admin/Owner can also view the page. Audit events contain actor, UTC timestamp, record type, record ID and Added/Modified/Deleted action; no password or data field values. *Legacy events cannot be reconstructed.* Changes performed without EF async saves (e.g. direct SQL) are not covered.
5. Limited broad `/api/admin` endpoints to organization-level management, removing Department Heads from global-data endpoints; Department Heads retain dedicated scoped `/api/team-scope` APIs. Restricted web user mutations and mobile admin write APIs to Admin/Owner/SuperAdmin roles, leaving Auditor/CountryHead read-only for these actions. Shift approvals are not available to department heads through global API.
6. Includes fix for previously reported CS8122 expression-tree pattern-match error in ShiftRequestsController.cs.
7. Other login, attendance, network verification, device binding, announcement and shift logic retained.

## Security review — important limitations

This is a **targeted source-level review, NOT a penetration test or complete security audit**. Code compilation, browser rendering and mobile runtime testing require Windows .NET/Flutter SDKs and a phone, which were not available in the packaging environment.

- Development configuration includes a known JWT signing key. **Use a cryptographically random secret via secure environment variables in production**; rotate it, never publish it to a repo or client.
- Development seeder contains a well-known initial `admin` password. **Change it before deploying**. Do not expose the development server directly to the internet.
- Local dev server uses HTTP and relaxed geofence config. Production must use HTTPS, properly configured restricted CORS and a tested geofence/office router policy.
- Audit records in the current implementation are application-level metadata rather than immutable tamper-proof records. Strong audit requirements need append-only/remote storage, retention, alarms and privileged deletion safeguards.
- Device binding is not equivalent to hardware-attested identity; perform security testing before high-trust production rollout.
- All route authorization should be checked against a matrix in real tests, including country head, auditor, receptionist, every department head, and direct API calls. Existing APIs not in scope may still need hardening.
- Do not assume all Flutter red-screen / overflow issues are eliminated by a web sidebar CSS patch.

## Local smoke checks

1. `dotnet build` and `dotnet run` from `backend/ScholarshipHive.Server`.
2. Browser at 90% zoom: scroll sidebar and confirm bottom Logout is visible, icons are monochrome, routes work.
3. Auditor web login should open Audit Activity; use actor/action/date filters. Test that auditor cannot mutate Users via direct POST/DELETE.
4. Head of Processing: add/remove own employee; employee disappears from **active** team roster, history preserved; verify 403/404 when trying to remove Marketing employee using direct API or URL.
5. Head of Marketing: check only Marketing and Interns; cannot delete Head/Owner/admin accounts.
6. Re-test authenticated login/logout, device check-in/out, announcements, shift requests and reception. Backup local SQLite database before replacing a working version.
