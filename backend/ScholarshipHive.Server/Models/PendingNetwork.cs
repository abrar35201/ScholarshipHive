namespace ScholarshipHive.Server.Models;

/// A Wi-Fi network (BSSID) that a device has actually tried to connect from, but which
/// isn't on the approved router list yet. Captured automatically from real login/check-in
/// attempts so an admin can approve it with one click, without needing to physically
/// scan that network from their own machine.
public class PendingNetwork
{
    public int Id { get; set; }

    public string Bssid { get; set; } = string.Empty;
    public string? Ssid { get; set; }
    public string? LastSeenFromIp { get; set; }

    public int AttemptCount { get; set; } = 1;
    public DateTime FirstSeenAt { get; set; } = DateTime.UtcNow;
    public DateTime LastSeenAt { get; set; } = DateTime.UtcNow;
}
