namespace ScholarshipHive.Server.Dtos;

/// Present/Absent only — see AttendanceController for why exact timings
/// aren't included here.
public class MyAttendanceDayDto
{
    public DateOnly Date { get; set; }
    public bool Present { get; set; }

    /// "Present" | "Late" | "Absent" | "Extra" (weekend, but still checked in) |
    /// "Weekend" (weekend, no attendance) — same vocabulary as the admin calendar's
    /// per-day status, so the employee's own calendar can tell Late apart from a
    /// plain on-time Present instead of collapsing both into the one Present bool.
    public string Status { get; set; } = "Absent";
}
