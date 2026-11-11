using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Services;

/// Production data (2026-08-05) showed employees on a single, unchanged router
/// still getting checked out and back in every 1-3 minutes all day — the 15s
/// heartbeat simply isn't that reliable in practice (brief signal dips, OS
/// throttling, server hiccups routinely exceed even 40s), and treating every
/// missed heartbeat as "they left the building" was producing dozens of bogus
/// check-out/check-in pairs per person per day.
///
/// The office geofence (see OfficeGeofenceService/AllowedLocation) is now the
/// primary "did they actually leave" signal — its exit trigger calls the
/// checkout endpoint directly, near-instantly, and is GPS-based rather than
/// dependent on this Wi-Fi ping cadence at all. This sweep's job has shrunk to
/// being a distant safety net: it only needs to catch someone whose phone lost
/// ALL connectivity for a long stretch AND has no geofence coverage (location
/// permission denied, etc.) — not routine Wi-Fi flakiness while they're still
/// at their desk.
///
/// [StaleThreshold] has to stay comfortably ABOVE the real gap between
/// successful pings under completely normal operation, or this sweep becomes
/// the exact bug it was written to fix. The client moved (2026-08-07, two days
/// after the threshold above was tuned) to a WorkManager-based backup loop
/// that only runs every 15 minutes — Android's own floor for periodic
/// work — with an FCM watchdog nudging a one-off check only once that gap
/// passes 12 minutes (see attendance_check_worker.dart, fcm_service.dart).
/// Nobody ever went back and widened this threshold to match, so it was
/// firing on essentially every single normal cycle: closing the attendance,
/// then immediately "reopening" it (see EnsureTodayAttendanceAsync) the
/// moment the next perfectly-routine 15-minute ping landed, logging a brand
/// new CheckIn each time — the dozens-of-pairs-per-day-for-someone-who-never-
/// left symptom this comment used to claim was already fixed. 30 minutes
/// covers a full periodic cycle plus a full watchdog-nudge cycle, even if
/// both landed late, while still closing out a session within a reasonable
/// time if a phone genuinely goes dark with no geofence coverage at all.
public class StaleAttendanceCheckoutService : BackgroundService
{
    private static readonly TimeSpan StaleThreshold = TimeSpan.FromMinutes(30);
    private static readonly TimeSpan SweepInterval = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan MaximumElapsedShift = TimeSpan.FromHours(10);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<StaleAttendanceCheckoutService> _logger;

    public StaleAttendanceCheckoutService(IServiceScopeFactory scopeFactory, ILogger<StaleAttendanceCheckoutService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(SweepInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await SweepAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Stale attendance sweep failed");
            }
        }
    }

    private async Task SweepAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var realtime = scope.ServiceProvider.GetRequiredService<RealtimeNotifier>();

        var cutoff = DateTime.UtcNow - StaleThreshold;

        // Not scoped to `a.Date == today` — a session left open on a PAST
        // business day (the device went dark for good: crashed, uninstalled,
        // powered off with no reconnect ever) used to never get swept at all
        // once the day rolled over, since this only ever looked at today's
        // rows. That row then sat "still open" forever — the Hours tab and
        // the admin shift-progress card would show it accumulating (capped at
        // one business day's worth, but never actually closed) days after the
        // fact, for a session that very obviously ended. `LastPingAt < cutoff`
        // alone is enough of a gate for a past-day row too: its last real ping
        // is necessarily well over [StaleThreshold] old by the time a LATER
        // business day has already started.
        var tenHourCutoff = DateTime.UtcNow - MaximumElapsedShift;
        var stale = await db.Attendances
            .Where(a => a.CheckOutTime == null && (a.LastPingAt < cutoff || a.CheckInTime <= tenHourCutoff))
            .ToListAsync(ct);

        if (stale.Count == 0) return;

        foreach (var attendance in stale)
        {
            // Re-check against the database right before writing — a genuine check-in can
            // land on this exact row between the query above and this write (the sweep only
            // runs every 10s, plenty of time for a reconnect), and blindly trusting the
            // earlier snapshot would silently overwrite that fresh check-in with a bogus
            // checkout, logging a second CheckOut with no CheckIn in between.
            await db.Entry(attendance).ReloadAsync(ct);
            if (attendance.CheckOutTime is not null ||
                (attendance.LastPingAt >= cutoff && attendance.CheckInTime > tenHourCutoff))
            {
                continue;
            }

            // Enforce a hard wall-clock limit even when the phone never sends checkout.
            // A stale phone is checked out at its last known ping; an otherwise live
            // phone is checked out at the 10-hour deadline.
            var autoCheckoutAt = attendance.CheckInTime.Add(MaximumElapsedShift);
            if (attendance.LastPingAt < autoCheckoutAt) autoCheckoutAt = attendance.LastPingAt;
            if (autoCheckoutAt < attendance.CheckInTime) autoCheckoutAt = attendance.CheckInTime;
            attendance.CheckOutTime = autoCheckoutAt;
            db.LoginHistories.Add(new LoginHistory
            {
                UserId = attendance.UserId,
                EventType = LoginHistoryEvent.CheckOut,
                Timestamp = autoCheckoutAt,
                Bssid = attendance.DeviceBssid
            });
        }

        await db.SaveChangesAsync(ct);
        await realtime.NotifyAsync("attendance");
        _logger.LogInformation("Auto-checked-out {Count} stale attendance(s)", stale.Count);
    }
}
