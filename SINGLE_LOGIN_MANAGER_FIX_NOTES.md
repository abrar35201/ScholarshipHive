# ScholarshipHive — Single Sign-In + Management Roles

- No visible separate admin/management login button. One Sign In route first verifies credentials on the server.
- Approved Admin, Owner, Marketing Head, Processing Head, Country Head and Auditor: no Wi-Fi restriction, no attendance check-in.
- Employees (and non-manager accounts): normal approved-network and device-binding restrictions stay in place.
- Backend returns code `office_network_required` and HTTP 409 only AFTER successful password verification for non-managers; password failures remain HTTP 401.
- Head of Processing and Head of Marketing have the main Admin dashboard in Flutter and management authorization on web/API.
- Only the original reserved `admin` can create/appoint the Head of Marketing or Head of Processing; deletion and demotion of original admin are still forbidden.
- Previously created Head-of-Processing accounts automatically receive broader privileges under the updated policy: review them before deploying.
- Legacy admin login endpoint remains server-side for compatibility, but there is no alternate public-facing sign-in action.
- Back up the working SQLite database before changing versions.

## Limitations
Full .NET/Flutter compilation and live device testing must be run locally (SDKs not available in this environment). Check all API policy boundaries before production deployment.
