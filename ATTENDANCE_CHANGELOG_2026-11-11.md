# ScholarshipHive attendance patch (2026-11-11)

- Seeded **admin** user remains Wi-Fi-independent and attendance-exempt.
- Other active approved roles (second Admins, Owners, SuperAdmins, Country Head, Heads, Auditor, Receptionist and Employees) use existing approved-router/geofence/device-bound mobile check-in and check-out.
- Mobile remote management login is root-admin-only; other accounts fall back to the normal BSSID-verified login. Existing web MVC routes not changed.
- Android connectivity change stores Wi-Fi departure even if internet is completely disabled. On reconnect a pending departure is sent with authenticated check-in; backend validates JWT, device binding, approved network and location gate before reconciling. Timestamp is bounded by last server heartbeat and present time, to avoid negative/out-of-order history.
- Existing mobile network watchdog's 15-minute Wi-Fi grace changed to no grace for a confirmed unapproved network. Ambiguous/masked BSSID and unreachable-backend conditions still do NOT count as a departure by themselves.
- Hours/attendance lists include non-root administrative/management roles, instead of only Employee.
- No database schema change and no migration added.

## Known limitations / test before release

- Android may delay callbacks while the app is killed, battery-restricted, or in deep sleep; exact second of disconnect cannot be guaranteed while all networking is off. Server stale sweep still runs as fallback.
- Retroactively reported departure uses the device's timestamp, clamped against the server's last confirmed heartbeat. Treat disputed payroll gaps as needing audit; a phone clock is not a trusted time source.
- Original web MVC authentication paths are untouched: browser cannot verify Android BSSID, so web access for managers needs a separate office-access policy if strict network enforcement in browsers is required.
- A history event records a checkout on network departure, not necessarily the employee's final daily sign-out. Admin Hours detail shows accumulated intervals; no distinct final-signout flag has been introduced.
- Test secondary Admin/Head/Auditor/Receptionist login/attendance, disconnected/reconnected Wi-Fi, GPS exit, absence of false router-handoff gaps, device reset, existing leave/shift, Audit Activity and Gemini API. No live .NET/Flutter build was possible in the authoring environment.
