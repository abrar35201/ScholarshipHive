# Always runs the backend bundled with THIS extracted ZIP, not an older copy.
$ErrorActionPreference = "Stop"
$server = Join-Path $PSScriptRoot "backend\ScholarshipHive.Server"
if (-not (Test-Path (Join-Path $server "ScholarshipHive.Server.csproj"))) { throw "Backend project missing: $server" }
$port = Get-NetTCPConnection -LocalPort 5080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($port) { Write-Host "Port 5080 is already in use by PID $($port.OwningProcess). Stop the old backend (Ctrl+C) first." -ForegroundColor Red; exit 1 }
Set-Location $server
Write-Host "Using FIXED backend: $server" -ForegroundColor Green
dotnet restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dotnet build --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dotnet run --no-build
