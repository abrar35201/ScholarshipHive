using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;

namespace ScholarshipHive.Server.Services;

/// Nudges every logged-in device with a silent FCM push on a steady cadence — deliberately
/// EVERY device with a registered token, not just ones already checked in. An employee who
/// arrives at the office with the app's background service already dead (killed overnight by
/// an OEM battery manager, never checked in at all) needs waking up just as much as someone
/// already checked in who might go quiet — restricting this to "already checked in" devices
/// would silently exclude exactly the case that needs it most.
/// The mobile side's background handler (see fcm_service.dart) also uses each wake-up as a
/// chance to resurrect its own foreground service and geofence registration if either died,
/// independent of whatever the mobile app's own foreground-service timer is (or isn't)
/// managing to do on its own — see FcmPushService's doc comment for why this channel is
/// more resistant to OEM battery restrictions than our own alarms/timers.
public class FcmWakeService : BackgroundService
{
    // Every device with a token gets a wake on this cadence, 24/7 — this is a safety net for
    // the 15-minute WorkManager backup loop going quiet on some OEM, not the primary signal
    // (the geofence transition is), so it doesn't need to be anywhere near that frequent.
    // A previous value of 45 seconds meant every logged-in device re-registered its geofences
    // (see office_geofence_service.dart) ~1900 times/day; on Android, re-registering a
    // geofence while already standing inside it re-fires the initial ENTER trigger every time,
    // which made the brief foreground-service promotion for the Wi-Fi check visibly flap
    // on/off every 45 seconds for anyone sitting still in the office.
    private static readonly TimeSpan WakeInterval = TimeSpan.FromMinutes(10);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<FcmWakeService> _logger;

    public FcmWakeService(IServiceScopeFactory scopeFactory, ILogger<FcmWakeService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var scope = _scopeFactory.CreateScope();
        var fcm = scope.ServiceProvider.GetRequiredService<FcmPushService>();
        if (!fcm.IsEnabled)
        {
            _logger.LogInformation("FcmWakeService is idle — Firebase isn't configured.");
            return;
        }

        using var timer = new PeriodicTimer(WakeInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await WakeAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "FCM wake sweep failed");
            }
        }
    }

    private async Task WakeAsync(CancellationToken ct)
    {
        using var sweepScope = _scopeFactory.CreateScope();
        var db = sweepScope.ServiceProvider.GetRequiredService<AppDbContext>();
        var fcm = sweepScope.ServiceProvider.GetRequiredService<FcmPushService>();

        var tokens = await db.Users
            .Where(u => u.IsActive && u.FcmToken != null)
            .Select(u => u.FcmToken)
            .ToListAsync(ct);

        foreach (var token in tokens)
        {
            await fcm.SendWakePingAsync(token!, ct);
        }
    }
}
