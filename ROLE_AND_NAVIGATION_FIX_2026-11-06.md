# ScholarshipHive role / navigation fix (2026-11-06)

- HeadOfProcessing has Owner-equivalent **broad management pages** in web/Flutter and corresponding broad API policies. Role stays distinct in database.
- Only original `admin` can create/promote a new HeadOfProcessing; delegated managers can manage assigned head as permitted by existing rules. `admin` remains undeletable.
- Receptionist login for cookie-authenticated web portal stays supported: `/Account/Login` -> `/Reception/Index`. Reception pages remain under their own authorization.
- Fixed reception mobile bottom-sheet navigation: saving a visitor or consent now pops its actual modal sheet, not the parent screen.
- Fixed admin mobile drawer navigation after closing drawer to avoid using a deactivated BuildContext.
- Preserved announcements and login announcement popup.

## Suggested regression checks
1. Original admin logs in web and mobile; create HeadOfProcessing, then login as HeadOfProcessing and browse Dashboard, Team, Reports, Shifts, Network and AI screens.
2. Login as Receptionist via web `/Account/Login`; create visitor and consent; also test mobile modal save and Android hardware Back.
3. Login as Owner and try to create HeadOfProcessing (must be denied).
4. Try to edit/delete original `admin` as HeadOfProcessing (must be denied).
5. Employee attendance / announcements / device reset regression tests.

No .NET/Flutter SDK available during package creation; builds and actual device/navigation tests must be run locally.
