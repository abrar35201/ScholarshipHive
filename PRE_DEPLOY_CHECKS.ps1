# Run from the extracted ScholarshipHive project root with .NET 10 / Flutter installed.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
Write-Host 'Checking ASP.NET Core .NET 10 backend ...'
dotnet restore '.\backend\ScholarshipHive.Server\ScholarshipHive.Server.csproj'
if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed' }
dotnet build '.\backend\ScholarshipHive.Server\ScholarshipHive.Server.csproj' -c Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed' }
Push-Location '.\mobile'
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    flutter analyze --no-fatal-infos --no-fatal-warnings
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analyzer found errors' }
    $serverUrl = 'https://scholarshiphive-backend-production-526c0ddb.up.railway.app'
    flutter build apk --debug "--dart-define=API_SERVER_URL=$serverUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed' }
    flutter build web --release "--dart-define=API_SERVER_URL=$serverUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
} finally { Pop-Location }
Write-Host 'Build checks passed. Still verify PostgreSQL migration and live login before production release.'
