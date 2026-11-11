namespace ScholarshipHive.Server.Models;

/// Whether a device authenticated with a password (login) or silently re-authenticated
/// with a stored token (checkin) is an implementation detail the admin doesn't need to
/// see — both just mean "arrived." So there are only two events: CheckIn and CheckOut,
/// which should always alternate for a given user (one CheckIn, then the next event for
/// them is always a CheckOut, and vice versa).
public enum LoginHistoryEvent
{
    CheckIn = 0,
    CheckOut = 1
}

/// A full audit trail of every check-in/check-out event, independent of the daily
/// Attendance summary — so an admin can see exactly how many times and when a user
/// was active, not just the first check-in and last check-out of the day.
public class LoginHistory
{
    public int Id { get; set; }

    public int UserId { get; set; }
    public User? User { get; set; }

    public LoginHistoryEvent EventType { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public string? Bssid { get; set; }
}
