# Role, dashboard and announcement fixes (6 Nov 2026)

- Original `admin` account protection preserved.
- Head of Marketing now included in broad web and Flutter manager authorization, and routes to Today dashboard. Root admin only may create/appoint Head of Marketing; existing marketing grant/revoke retained.
- Head of Processing and Head of Counselors route to department-only TeamScope web/mobile pages and department-only user listing/creation/edit and attendance/report history; access to global admin controllers removed.
- Their announcements are forced to their department, while Admin/Owner/Marketing Head can target all departments.
- Browser navigations to `/api/announcements` with an authenticated cookie redirect to the MVC Announcements page instead of presenting a JWT 401. Mobile bearer-token access remains unchanged.
- Existing dashboard is database-derived, with 20-second refresh fallback; empty/zero statistics are displayed as zero when attendance has not been recorded. No fabricated data.
- Mobile departmental add-user action uses `/api/team-scope/employees`.

## Testing needed
Run `dotnet build`, `flutter analyze`, and verify role access, notices and attendance using separate test accounts. No .NET or Flutter SDK was available in the build environment. Preserve existing production database and backups.

- Marketing admin grant promotes a Marketing Employee to HeadOfMarketing (full management); revoke demotes to Employee. Historic Marketing users with Admin role can also be revoked.
