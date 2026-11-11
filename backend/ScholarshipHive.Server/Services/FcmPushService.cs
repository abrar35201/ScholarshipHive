using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;

namespace ScholarshipHive.Server.Services;

/// Sends silent "please check your network now" pushes over Firebase Cloud Messaging —
/// a wake path that rides on Google Play Services' own Doze-exempt delivery channel,
/// so it reaches a phone even when our own foreground-service timer has been throttled
/// or killed by an aggressive OEM battery manager. This is a supplement to, not a
/// replacement for, the existing foreground service + office geofence.
///
/// Firebase credentials aren't configured in every environment (e.g. before the Firebase
/// project existed at all, or a local dev box without the secret) — every method here is a
/// deliberate no-op rather than a startup crash when that's the case, since the rest of the
/// attendance system must keep working with or without this feature enabled.
public class FcmPushService
{
    private readonly ILogger<FcmPushService> _logger;
    private readonly FirebaseApp? _app;

    public FcmPushService(IConfiguration configuration, ILogger<FcmPushService> logger)
    {
        _logger = logger;

        var serviceAccountJson = configuration["Firebase:ServiceAccountJson"];
        if (string.IsNullOrWhiteSpace(serviceAccountJson))
        {
            _logger.LogWarning("Firebase:ServiceAccountJson is not configured — FCM wake pushes are disabled.");
            return;
        }

        try
        {
            _app = FirebaseApp.Create(new AppOptions
            {
                Credential = CredentialFactory.FromJson<ServiceAccountCredential>(serviceAccountJson).ToGoogleCredential()
            }, "ScholarshipHiveFcm");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize FirebaseApp — FCM wake pushes are disabled.");
        }
    }

    public bool IsEnabled => _app is not null;

    /// Fire-and-forget from the caller's perspective: a bad/expired token or a transient FCM
    /// error must never take down whatever background sweep is trying to wake this device up.
    public async Task SendWakePingAsync(string fcmToken, CancellationToken ct = default)
    {
        if (_app is null) return;

        var message = new Message
        {
            Fid = fcmToken,
            Data = new Dictionary<string, string> { ["type"] = "wake_check" },
            Android = new AndroidConfig
            {
                Priority = Priority.High,
                // No Notification block anywhere on this message — this must stay a silent,
                // background-only data push, never a visible notification.
            },
        };

        try
        {
            await FirebaseMessaging.GetMessaging(_app).SendAsync(message, ct);
        }
        catch (FirebaseMessagingException ex)
        {
            _logger.LogWarning(ex, "FCM wake push failed for a token (likely stale/unregistered).");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error sending FCM wake push.");
        }
    }

    /// A real, visible notification — unlike SendWakePingAsync, this shows up in the
    /// phone's notification tray. Used for admin-initiated messages (e.g. "ask for
    /// more detail" on a report) where the employee actually needs to see something.
    public async Task SendNotificationAsync(string fcmToken, string title, string body, CancellationToken ct = default)
    {
        if (_app is null) return;

        var message = new Message
        {
            Fid = fcmToken,
            Notification = new Notification { Title = title, Body = body },
            Android = new AndroidConfig { Priority = Priority.High },
        };

        try
        {
            await FirebaseMessaging.GetMessaging(_app).SendAsync(message, ct);
        }
        catch (FirebaseMessagingException ex)
        {
            _logger.LogWarning(ex, "FCM notification failed for a token (likely stale/unregistered).");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error sending FCM notification.");
        }
    }
}
