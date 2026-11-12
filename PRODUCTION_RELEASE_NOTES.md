# ScholarshipHive — Safe Source Update (12 November 2026)

This package is based on the exact ScholarshipHive_Source_Code.zip the user uploaded.

## Included
- Department Head monthly employee hours: select employee, then see that person's date-by-date check-in, check-out, worked minutes and gaps, for a selected month. Web and Flutter. Server-side department filtering retained, including Marketing/Interns scope. Department combined totals removed from the primary view.
- Department Head WEB sidebar "My Shift Requests" link hidden. Original login-screen off-network shift request and server-side request features retained unchanged.
- Calling Team digital application DRAFTS: 14 country/policy PDF templates from the user-supplied Google Drive folder, selectable in Web and Android. Employee must be active, approved, Employee role, and Calling department. Server-side rules enforce access. Other departments cannot list/view/create/download these PDFs through the new endpoints.
- Saved form details are separate secure records, not a filled or signed copy of the PDF. Review each original PDF and obtain signatures externally. PDF sources are unmodified and private (not under wwwroot).
- Additive database migration 20261112223500_AddCallingFormEntries adds a new table and index; no existing tables/records are deleted.

Note: The shared Drive folder's Czech Republic/Austria subfolder contained no accessible files.

## Production safety
- Not built or executed with .NET 10 or Flutter here: those toolchains are unavailable in this runtime. Static structure and original PDF integrity checks were performed only. No live production account/database was accessed. NO CODE WAS PUSHED OR DEPLOYED.
- The new migration will run at app startup if the existing production startup calls Database.MigrateAsync(). Take a PostgreSQL backup and first deploy to staging/test against a copy of production data.
- Check the actual legal form templates and any field coverage/signature requirements before using them as a replacement for signed paper/PDF consent forms. This release records draft data, not electronic legal acceptance.
- Existing unrelated broken links could not be diagnosed without a reproducible URL and HTTP/log details; no speculative fixes were made.

## Apply
1. Extract ScholarshipHive_Changes_Only.zip anywhere on your laptop.
2. Open PowerShell in the extracted directory (the one containing Apply-Updates.ps1).
3. Run:
     powershell -ExecutionPolicy Bypass -File .\Apply-Updates.ps1 -TargetProject "C:\Users\Nabeel Ahmad\Downloads\Finalproject_ATMS\ScholarshipHive"
   This checks all original file hashes against the uploaded snapshot, requires a clean Git working tree, makes an external backup, and refuses to overwrite conflicting files.
4. In the project folder run:
     cd backend\ScholarshipHive.Server
     dotnet restore
     dotnet build -c Release
     dotnet ef migrations has-pending-model-changes
     cd ..\..\mobile
     flutter pub get
     flutter analyze
     flutter build apk --debug --dart-define=API_SERVER_URL=https://scholarshiphive-backend-production-526c0ddb.up.railway.app
5. Test Calling employee, non-Calling employee, Head of Processing/Marketing and disallowed cross-department access using a staging PostgreSQL database.
6. Only once tests pass: git status; git add relevant files; git commit; git fetch origin; git status -sb; git push origin main (NEVER force-push).
7. Confirm Railway latest commit deployed. Existing Android installations need a new Flutter build/APK.
