# Critical fixes — November 6, 2026

- Announcements MVC path is now explicitly `/Announcements`; API remains `/api/announcements` for JWT clients. Removed the MVC→API self-redirect caused by same-name controller link generation. Web links and POST forms use explicit MVC URLs with antiforgery tokens.
- Reserved `admin` account now uses remote management login on ordinary mobile Sign In, without requiring office Wi-Fi or attendance. Other authorized managers can use the existing management login link. Employee login remains subject to approved Wi-Fi/device policies.
- Opening `/NetworkSettings/Create` via GET safely returns to the modal page instead of seeking a non-existent Razor view. Invalid POST data stays on Network Settings with the modal and validation errors.
- Dashboard refresh keeps the Refresh now button after polling and shows the HTTP status if fetch fails. Numbers still reflect REAL database events, not fabricated check-ins.

## Test steps

1. Start backend with `dotnet build` then `dotnet run`. Open `/Announcements` (NOT `/api/announcements`) and publish a notice. Verify browser does not redirect in circles.
2. Visit `/NetworkSettings/Create`; it must return to `/NetworkSettings`. Try an invalid/duplicate BSSID from the modal; it must show a validation error and not a black exception page.
3. Launch mobile with adb reverse, enter `admin` credentials and tap Sign In while on non-approved Wi-Fi. Admin should enter management dashboard. Employee accounts must still be Wi-Fi-gated.
4. Change attendance in the database through the app and verify dashboard values refresh within ~20 seconds. If attendance does not change, zero graphs are expected.

### Validation limitation
Archive/file checks do not substitute for a real .NET compilation, Flutter analysis and phone tests, which were not available here. Do not deploy without these checks.
