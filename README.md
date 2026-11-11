# ScholarshipHive

A production employee attendance and workforce management platform, built as a hybrid ASP.NET Core backend paired with a Flutter mobile app. It replaces manual attendance tracking with geofenced, network-verified check-ins, real-time admin visibility, and automated analytics — currently deployed and in active company-wide use.

## Overview

ScholarshipHive solves a simple but recurring problem for organizations with distributed or shift-based staff: knowing, reliably and in real time, who is actually present, when they arrived, and how attendance trends look over time — without relying on manual registers or trust-based self-reporting.

The system is split into two cooperating halves that share one database:

- **Backend** (`backend/ScholarshipHive.Server`) — an ASP.NET Core application that is simultaneously a server-rendered admin panel (Razor views, cookie authentication) for administrators on the web, and a JSON REST API (JWT authentication) that powers the mobile app for both employees and admins.
- **Mobile app** (`mobile/`) — a Flutter application (Android-first) used by employees to check in/out and submit daily reports, and by admins to manage the whole organization from their phone with the same functionality as the web panel.

## Key Features

**Attendance & Check-in**
- Geofenced, Wi-Fi-BSSID-verified check-in — an employee can only check in while connected to a Wi-Fi network an admin has explicitly approved, identified by the router's hardware BSSID (not its network name or password, which can change without breaking access).
- Automatic check-in/check-out: the app detects approved networks in the background and checks the user in or out without requiring a manual tap.
- Server-enforced business rules: one attendance record per calendar day, accurate check-in/check-out timestamps, and a configurable grace period for lateness relative to each employee's assigned shift.
- Day shift (9:30 AM – 5:30 PM) and Night shift (6:00 PM – 2:00 AM) support, with admin-configurable per-employee shift assignment reflected consistently across the dashboard, analytics, and mobile app.

**Reporting**
- Optional daily reports from employees — free text, an attached file of any type, or both — reviewable by admins with the original file downloadable exactly as submitted.

**Admin Dashboard & Analytics**
- Real-time dashboard: total users, checked-in count, today's reports, active routers, and pending approvals, updating live via SignalR (with a polling safety net) with no manual refresh.
- Attendance-rate and shift-health analytics, computed from each employee's actual earliest attendance record rather than an unreliable account-creation timestamp, so percentages stay accurate even for accounts migrated from a previous system.
- A daily arrival-time histogram (check-ins per hour) reflecting genuine hourly volume rather than a monotonically increasing running total.
- Full per-user audit history: profile, attendance history, submitted reports, and a complete login/check-in/logout event log with exact timestamps.

**User & Access Management**
- Self-registration (gated to approved networks) with admin approval before first login, or direct admin-created accounts.
- Role-based access: the web admin panel is admin-only; the mobile app serves both roles from a single login, routing each to the appropriate experience.
- Account lockout after 5 failed password attempts (15-minute cooldown, admin-unlockable), hashed passwords, and a self-service forgot-password flow.

**Notifications & Real-Time Updates**
- Firebase Cloud Messaging push notifications, including a daily welcome/check-in reminder.
- Live UI updates across both the web admin panel and every tab of the mobile admin panel the moment underlying data changes.

## Architecture

```
mobile/ (Flutter)                    backend/ScholarshipHive.Server (ASP.NET Core)
├─ Employee UI                       ├─ Legacy MVC (Razor views, cookie auth) — web admin panel
├─ Admin UI (mirrors web panel)      ├─ REST API (JWT auth) — /api/... consumed by mobile
├─ Background Wi-Fi/geofence watch   ├─ SignalR hub — real-time push to both clients
└─ Firebase push notifications       ├─ EF Core + PostgreSQL — single shared data layer
                                      └─ Hosted on Railway (Docker), 24/7, independent of any
                                         developer machine
```

Both the MVC admin panel and the REST API sit in the same ASP.NET Core project and share the same `AppDbContext`, so the web panel and the mobile app are always looking at identical, consistent data — there is no synchronization step between them.

## Tech Stack

| Layer | Technology |
|---|---|
| Backend framework | ASP.NET Core (.NET 10), hybrid MVC + Web API |
| ORM / Database | Entity Framework Core, PostgreSQL |
| Real-time | SignalR |
| Auth (web) | Cookie authentication |
| Auth (API/mobile) | JWT bearer tokens |
| Push notifications | Firebase Cloud Messaging |
| Hosting | Railway (Docker-based deployment) |
| Mobile framework | Flutter (Dart), Android-first |
| Mobile state management | Provider |
| Mobile networking | Dio, SignalR (.NET Core client for Flutter) |
| Mobile platform integrations | `geolocator`, `native_geofence`, `wifi_scan`, `network_info_plus`, `flutter_foreground_task`, `workmanager`, `local_auth`, `flutter_secure_storage` |
| Charts | `fl_chart` |

## Project Structure

```
backend/ScholarshipHive.Server/
├─ Controllers/          MVC controllers (web admin panel)
│  └─ Api/                REST API controllers (Auth, Attendance, Admin, Reports, AuditReports)
├─ Services/              Business logic: analytics, dashboard aggregation, JWT issuing,
│                          FCM push, real-time notification dispatch, stale-session cleanup,
│                          Wi-Fi/network access rules, date/time handling
├─ Models/                EF Core entities (User, Attendance, Report, AllowedRouter, etc.)
├─ Dtos/                  Request/response contracts for the API and admin view models
├─ Data/                  AppDbContext, database seeding
├─ Migrations/            EF Core migrations
├─ Hubs/                  SignalR hub for real-time updates
├─ Views/                 Razor views for the web admin panel
└─ Dockerfile             Production container build

mobile/lib/
├─ screens/
│  ├─ login/, register/, onboarding/, account/     Auth & onboarding flows
│  ├─ home/, attendance/, report/                   Employee experience
│  └─ admin/                                         Full admin panel (dashboard, users,
│                                                      attendance, reports, network, shifts,
│                                                      hours, audit reports, AI assistant)
├─ services/               API client, geofence/network watcher, background task handling
├─ models/                 Client-side data models mirroring the backend DTOs
└─ core/                   Shared config (API base URL, shift utilities, etc.)
```

## Getting Started (Local Development)

**Backend**
```bash
cd backend/ScholarshipHive.Server
dotnet run
```
Runs against a local PostgreSQL instance by default; listens on your machine's LAN address so a physical device on the same network can reach it during development.

**Mobile app**
```bash
cd mobile
flutter run
```
`mobile/lib/core/api_config.dart` controls which backend URL the app talks to — point it at your local backend for development, or leave it at the production Railway URL to test against live data.

## Deployment

The backend is deployed as a Docker container to Railway, decoupled from any developer's machine — it and its PostgreSQL database run continuously regardless of whether a laptop is on.

```bash
cd backend/ScholarshipHive.Server
railway up
```

Configuration (database connection string, JWT signing key, Firebase service account) is injected via Railway environment variables and never committed to source control. ASP.NET Core Data Protection keys are persisted to the same PostgreSQL database (rather than the container's ephemeral local disk), so authentication cookies and antiforgery tokens survive redeploys without forcing users to log in again.

The mobile app is published to the Google Play Store.

## Security

- Wi-Fi network approval is BSSID-based, independent of network name or password.
- Passwords are always hashed, never stored in plain text.
- Failed-login lockout (5 attempts / 15 minutes), with instant admin override.
- Employee accounts are rejected outright by the web login — only the mobile app accepts employee credentials, enforced server-side, not just hidden in the UI.
- Secrets (connection strings, signing keys, Firebase credentials) live only in the hosting platform's environment configuration.

## Roadmap Notes

- Background check-in/check-out currently requires the app to remain running (foreground or backgrounded); it pauses if the app is fully closed by the user and resumes on next open. A native Android foreground service would remove this limitation.

---

For day-to-day operational instructions (router approval workflow, deployment commands, user management), see [`SETUP.md`](SETUP.md).






# ScholarshipHive - Backend + Web Admin Panel

# Step 1: Backend folder open karo
cd "C:\Users\Nabeel Ahmad\Desktop\ScholarshipHive\ScholarshipHive\backend\ScholarshipHive.Server"

# Step 2: Backend aur Web dono start karo
dotnet run

# Web Admin Panel:
# http://localhost:5080

# IMPORTANT: Terminal band mat karna


# ScholarshipHive - Flutter Mobile App in Chrome

# Step 1: Flutter project folder open karo
cd "C:\Users\Nabeel Ahmad\Desktop\ScholarshipHive\ScholarshipHive\mobile"

# Step 2: Flutter app Chrome par run karo
flutter run -d chrome --web-port=3000 --dart-define=API_SERVER_URL=http://localhost:5080

# Flutter App:
# http://localhost:3000

# IMPORTANT: Terminal band mat karna