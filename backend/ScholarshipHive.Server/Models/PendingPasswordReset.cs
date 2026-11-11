namespace ScholarshipHive.Server.Models;

/// A "forgot password" request an employee submitted — holds the desired new
/// password (already hashed) until an admin reviews and approves it. Never applied
/// automatically: this is deliberately a request, not a self-service reset, since the
/// whole point is that the employee can no longer prove who they are with a password.
/// One row per user — a second request just replaces the first rather than stacking.
public class PendingPasswordReset
{
    public int Id { get; set; }

    public int UserId { get; set; }
    public User? User { get; set; }

    public string NewPasswordHash { get; set; } = string.Empty;
    public string DeviceId { get; set; } = string.Empty;
    public DateTime RequestedAt { get; set; } = DateTime.UtcNow;

    /// Whether [DeviceId] matched the account's own HomeDeviceId at request time.
    /// A genuine reinstall, cleared app storage, or new phone means that match is
    /// simply unavailable — refusing the request outright in that case left anyone
    /// who needed this flow most (device changed AND forgot their password) with no
    /// way to recover at all. Now the request always reaches an admin either way;
    /// this is what tells them to actually verify the person's identity some other
    /// way (call them, ask in person) before approving one raised here false.
    public bool DeviceRecognized { get; set; } = true;
}
