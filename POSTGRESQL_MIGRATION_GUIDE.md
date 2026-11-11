# ScholarshipHive — PostgreSQL-only migration (2026-11-11)

## What changed (Roman Urdu)

- Application ab **sirf PostgreSQL** `Npgsql` use karti hai. `UseSqlite`, `EnsureCreated`, SQLite `PRAGMA` aur startup SQLite schema patches remove kiye gaye.
- PostgreSQL migration files **preserve** hain (Users, attendance, router/BSSID, geofence, reports, Reception, Leaves, Shift Requests, Announcements, Audit Events, user notices, DataProtectionKeys). `dotnet ef database update` se apply hoti hain.
- Flutter/web API URLs aur attendance, roles, HomeDeviceId checks **unchanged** hain.
- Existing SQLite records migrate karne ke liye read-only Python importer diya hai. User IDs, password hashes, check-in/out records, network settings, files, audit records aur DataProtectionKeys preserve karne ki koshish karta hai. No plaintext password conversion.
- Startup ke hardcoded admin/reviewer passwords aur dev JWT signing key remove kiye. **Fresh empty database** ke pehle startup par `Bootstrap:AdminPassword` (min 12 chars) set karo. Existing imported `admin` ka password **change nahi hota**.
- Importer only **empty, EF-migrated PostgreSQL DB** accept karta hai, transaction mein import karta hai, records/count verify karta hai, identity sequences reset karta hai, aur failure par rollback karta hai.

## Before starting

**Purana backend band karo.** Apne *current* SQLite database `ScholarshipHive.dev.db` ka backup banao. Agar `-wal` aur `-shm` files hain to unhein bhi saath rakho (SQLite WAL mein fresh transactions ho sakti hain). Is ZIP ke `LEGACY_SQLITE_BACKUP` mein uploaded ZIP ka snapshot hai, **zaroori nahi ke tumhare laptop ke latest records wahi hon**. Local fresh data migrate karna ho to backend stop karke fresh SQLite + sidecars ko ek folder mein copy karo.

PostgreSQL 18 / pgAdmin 4 installed ho. PostgreSQL `postgres` superuser se **new empty** database `scholarshiphive` aur login role `scholarshiphive_app` create karo. pgAdmin Query Tool (postgres database):

```sql
CREATE ROLE scholarshiphive_app WITH LOGIN PASSWORD 'CHOOSE_A_NEW_STRONG_PASSWORD';
```

Then pgAdmin UI -> Databases -> Create -> Database -> Name `scholarshiphive`, Owner `scholarshiphive_app`. Alternatively execute `CREATE DATABASE scholarshiphive OWNER scholarshiphive_app;` as a separate statement.

## Step 1 — secure local config (PowerShell)

Open PowerShell inside `ScholarshipHive/backend/ScholarshipHive.Server`:

```powershell
dotnet restore
# Password hidden; do NOT paste your real password into chat or a committed file.
$securePg = Read-Host 'PostgreSQL scholarshiphive_app password' -AsSecureString
$pgPassword = [System.Net.NetworkCredential]::new('', $securePg).Password
$connection = "Host=localhost;Port=5432;Database=scholarshiphive;Username=scholarshiphive_app;Password=$pgPassword"
dotnet user-secrets set 'ConnectionStrings:DefaultConnection' "$connection"
Remove-Variable securePg, pgPassword, connection

$secureJwt = Read-Host 'New JWT signing key (at least 32 chars)' -AsSecureString
$jwt = [System.Net.NetworkCredential]::new('', $secureJwt).Password
dotnet user-secrets set 'Jwt:Key' "$jwt"
Remove-Variable secureJwt, jwt
```

Gemini key on same Windows account, same UserSecretsId: previously configured `Gemini:ApiKey` should remain available. Verify its **presence without printing the value** if needed; never paste secrets into chat. For **new empty DB (no legacy data)** also set the bootstrap secret:

```powershell
$secret = Read-Host 'New admin password (12+ chars)' -AsSecureString
$password = [System.Net.NetworkCredential]::new('', $secret).Password
dotnet user-secrets set 'Bootstrap:AdminPassword' "$password"
Remove-Variable secret,password
```

## Step 2 — create PostgreSQL schema WITHOUT starting server

Inside server project folder:

```powershell
dotnet tool update --global dotnet-ef --version 10.0.10
dotnet ef database update
```

`PostgresDesignTimeFactory.cs` ensures this command uses PostgreSQL without starting the web app/seeding admin.

## Step 3 — OPTIONAL: import old SQLite data before first dotnet run

From project root `ScholarshipHive`:

```powershell
python .\tools\migrate_sqlite_to_postgres.py --sqlite '.\LEGACY_SQLITE_BACKUP\ScholarshipHive.dev.db' --inventory
python -m pip install 'psycopg[binary]'
$env:PGHOST='localhost'
$env:PGPORT='5432'
$env:PGDATABASE='scholarshiphive'
$env:PGUSER='scholarshiphive_app'
$secure = Read-Host 'PostgreSQL password for data import' -AsSecureString
$env:PGPASSWORD = [System.Net.NetworkCredential]::new('', $secure).Password
python .\tools\migrate_sqlite_to_postgres.py --sqlite '.\LEGACY_SQLITE_BACKUP\ScholarshipHive.dev.db' --execute
Remove-Item Env:\PGPASSWORD
Remove-Variable secure
```

If you have **newer** SQLite data on laptop, replace `--sqlite` path with that *stopped and backed-up* database. Do NOT run importer after the app has already seeded users or accepted new transactions; it intentionally refuses nonempty target tables. For first-time fresh install without legacy data, skip Step 3.

The importer fails if source data includes tables or nonnullable fields absent from PostgreSQL. That is intentional: never silently drop data.

## Step 4 — start web/backend

Inside server folder:

```powershell
dotnet build
if ($LASTEXITCODE -eq 0) { dotnet run }
```

Web: `http://localhost:5080`. Flutter Android via USB still:

```powershell
adb reverse tcp:5080 tcp:5080
flutter run -d YOUR_DEVICE_ID --dart-define=API_SERVER_URL=http://127.0.0.1:5080
```

If you use `dotnet run` under Development, `Attendance:RequireGeofence` is **false in existing appsettings.Development.json**, matching the previously working local setup. Production `appsettings.json` has `RequireGeofence=true`. This setting was not changed by this migration.

## Step 5 — pgAdmin 4 verification

1. Open pgAdmin 4 -> Servers -> PostgreSQL -> Databases -> `scholarshiphive` -> Schemas -> public -> Tables. Refresh.
2. Right-click DB -> Query Tool; run queries below:

```sql
SELECT "MigrationId" FROM "__EFMigrationsHistory" ORDER BY "MigrationId";
SELECT COUNT(*) AS users FROM "Users";
SELECT "Id", "Username", "Role", "IsActive", "IsApproved" FROM "Users" ORDER BY "Id";
SELECT COUNT(*) AS attendance_rows FROM "Attendances";
SELECT "UserId", "Date", "CheckInTime", "CheckOutTime" FROM "Attendances" ORDER BY "Date" DESC LIMIT 20;
SELECT "Name", "Bssid", "IsActive" FROM "AllowedRouters";
SELECT "Name", "RadiusMeters", "IsActive" FROM "AllowedLocations";
SELECT COUNT(*) AS audit_events FROM "AuditEvents";
SELECT COUNT(*) AS visits FROM "VisitorRecords";
SELECT COUNT(*) AS leaves FROM "LeaveRequests";
SELECT COUNT(*) AS announcements FROM "Announcements";
SELECT COUNT(*) AS notices FROM "UserNotices";
SELECT COUNT(*) AS reports FROM "Reports";
SELECT COUNT(*) AS report_files FROM "ReportFiles";
SELECT COUNT(*) AS data_protection_keys FROM "DataProtectionKeys";
```

Verify attendance time, gap after Wi-Fi off/on, one-device registration, admin/head/receptionist login, API Add/Remove, leave/shift, Reception consent, Audit Activity and Gemini chatbot via real UI. Database table counts alone do not prove business workflows.

## Deployment essentials

- Set `ConnectionStrings__DefaultConnection` from deployment secret manager (production PostgreSQL URI/connection string), `Jwt__Key` as a **new strong secret**, and `Gemini__ApiKey` via deployment secrets. Configure `Bootstrap__AdminPassword` only for first-time empty DB; do not expose in appsettings or repositories.
- For cloud PostgreSQL prefer `SSL Mode=Require` (or `VerifyFull` with certificate setup), restricted DB role, backups, monitoring, no publicly accessible unrestricted PG port.
- SQLite backup in `LEGACY_SQLITE_BACKUP` is a **sensitive historical data file**. **Exclude it from deployment artifacts, Git and sharing.** Do not publish root ZIP directly as a public site.
- For production, use `dotnet publish` from backend project folder; published server does not need the legacy backup.
- Keep `DataProtectionKeys` in the database so web cookies survive application restarts; preserve original DB snapshots offline before production cutover.

## What was / wasn't tested

- Static checks: provider switched to PostgreSQL-only; migrations retained; Python importer syntax/inventory; ZIP integrity and file preservation.
- Not executable here: actual .NET 10 restore/build, PostgreSQL connection/migrations, pgAdmin queries, Android device integration. Run all those locally before declaring production-ready.
