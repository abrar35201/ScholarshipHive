namespace ScholarshipHive.Server.Models;

public class Attendance
{
    public int Id { get; set; }

    public int UserId { get; set; }
    public User? User { get; set; }

    /// Calendar day this attendance record belongs to (server local date).
    public DateOnly Date { get; set; }

    public DateTime CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }

    /// Updated on every heartbeat (app calling Checkin while still on the approved
    /// network) — a client can't be trusted to always successfully notify the server
    /// the instant it loses all connectivity (there may be no network left to send
    /// that call over), so this is what a background sweep uses to notice someone
    /// went silent and auto-checkout them, instead of relying solely on the client.
    public DateTime LastPingAt { get; set; } = DateTime.UtcNow;

    public bool ReportSubmitted { get; set; } = false;

    public string? DeviceBssid { get; set; }

    public Report? Report { get; set; }
}
