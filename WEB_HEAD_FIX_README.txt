SCHOLARSHIPHIVE WEB HEAD EMPLOYEE FIX 2026-11-10 V3

1. Extract this ZIP to a NEW folder, do not merge with an older project.
2. Keep the existing SQLite database safe. Backup the database (and WAL/SHM if present) when the backend is stopped before migrating data. Never overwrite the production DB with the bundled sample.
3. Stop old backend (Ctrl+C), then in PowerShell:
   cd "<your extracted folder>\ScholarshipHive"
   powershell -NoProfile -ExecutionPolicy Bypass -File .\RUN_FIXED_BACKEND.ps1
4. Browse http://localhost:5080/TeamScope after signing in as a department head.
5. In browser View Source, HEAD_WEB_ROUTE_FIX_2026_11_10_V3 proves you're serving the new Razor view. Add must POST /TeamScope/Add and Remove must POST /TeamScope/Remove/{id}.

FIX: Mobile API controller class changed from TeamScopeController to TeamScopeApiController to prevent MVC route-generation collisions. API URLs unchanged: /api/team-scope/... . Web controller remains TeamScopeController, protected by TeamHeadWeb cookie policy and antiforgery. The Web dashboard action URLs are explicitly scoped to /TeamScope/..., return TempData confirmation, and never POST HTML form data to JSON API.

No change to attendance, device binding, shift logic, database schema, or mobile Flutter files.

Actual dotnet build and browser end-to-end testing not available in this environment; run the included script and verify login/create/remove on your machine.
