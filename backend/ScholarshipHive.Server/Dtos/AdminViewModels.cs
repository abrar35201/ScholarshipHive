using System.ComponentModel.DataAnnotations;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Dtos;

public record DepartmentHealth(string Department, int PresentToday, int ActiveEmployees, int ReportsThisMonth);

/// One cell in a single user's monthly attendance calendar (Attendance/Index,
/// only rendered once a specific user is selected). Status is one of:
/// "present", "late", "absent", "weekend" (Sunday — this app has no
/// configured working-days schedule, so Sunday-off is a fixed assumption,
/// not a per-user setting), or "future".
public record CalendarDay(int Day, DateOnly Date, string Status);

/// One row in the office-wide day log (Attendance/Index, office-wide mode) —
/// every active employee, whether or not they have an attendance record for
/// that day. Status is one of: "OnFloor", "CheckedOut", "Late", "Absent".
public record AttendanceRosterRow(int UserId, string Name, string Department, string? CheckInLabel, string? CheckOutLabel, string? DurationLabel, string Status);

public class LoginViewModel
{
    [Required]
    public string Username { get; set; } = string.Empty;

    [Required, DataType(DataType.Password)]
    public string Password { get; set; } = string.Empty;

    public string? Error { get; set; }
}

public class UserFormViewModel
{
    public int Id { get; set; }

    [Required, MaxLength(50)]
    public string Username { get; set; } = string.Empty;

    [MaxLength(100)]
    public string FullName { get; set; } = string.Empty;

    [DataType(DataType.Password), StrongPassword]
    public string? Password { get; set; }

    public UserRole Role { get; set; } = UserRole.Employee;
    public EmployeeDepartment Department { get; set; } = EmployeeDepartment.Calling;

    public bool IsActive { get; set; } = true;

    public bool IsApproved { get; set; } = true;
}

/// Backs the Shifts page's two apply actions — bulk (a whole department, or
/// whatever rows are checked) and the per-row individual edit both post this
/// same shape, they just differ in which of Department/UserIds is set.
public class ShiftAssignmentViewModel
{
    public EmployeeDepartment? Department { get; set; }
    public List<int> UserIds { get; set; } = new();

    [Required]
    public TimeOnly ShiftStartTime { get; set; } = new(9, 30);

    [Required]
    public TimeOnly ShiftEndTime { get; set; } = new(17, 30);

    public ShiftType ShiftType { get; set; } = ShiftType.Day;
}

public class RouterFormViewModel
{
    public int Id { get; set; }

    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Required, MaxLength(17)]
    [RegularExpression(@"^([0-9A-Fa-f]{2}[:\-]){5}([0-9A-Fa-f]{2})$", ErrorMessage = "Enter a valid MAC address, e.g. AA:BB:CC:DD:EE:FF")]
    public string Bssid { get; set; } = string.Empty;

    public bool IsActive { get; set; } = true;
}

public class LocationFormViewModel
{
    public int Id { get; set; }

    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Range(-90, 90)]
    public double Latitude { get; set; }

    [Range(-180, 180)]
    public double Longitude { get; set; }

    [Range(20, 2000)]
    public double RadiusMeters { get; set; } = 150;

    public bool IsActive { get; set; } = true;
}

public class DashboardViewModel
{
    public int TotalUsers { get; set; }
    public int CheckedInNow { get; set; }
    public int ReportsToday { get; set; }
    public int ConfiguredRouters { get; set; }
    public List<Attendance> RecentAttendance { get; set; } = new();

    /// One point per of the last 7 calendar days — how many distinct people
    /// had at least one attendance record that day.
    public List<ChartPoint> WeeklyHeadcount { get; set; } = new();

    /// Cumulative check-in count across the full business day (7 AM to 7 AM the
    /// next day), hourly — how the floor fills up, covering Night/Internship
    /// shifts too, not just an 08:00-10:30 morning window.
    public List<ChartPoint> ArrivalCurve { get; set; } = new();

    public int PresentOnTimeToday { get; set; }
    public int LateToday { get; set; }
    public int AbsentToday { get; set; }

    /// Day/Night shift breakdown — see ShiftHealth's doc comment for why
    /// Internship shift (the interns) is left out of this.
    public List<ShiftHealth> ShiftHealth { get; set; } = new();

    public string Period { get; set; } = "day";
    public int TotalActiveEmployees { get; set; }
    public int AwayCount { get; set; }
    public string AverageArrivalLabel { get; set; } = "—";
    public string AverageArrivalSublabel { get; set; } = "";
    public int AverageArrivalTrendMinutes { get; set; }
    public int ReportsFiledRate { get; set; }
    public string ReportsFiledFraction { get; set; } = "0 of 0";
    public int ReportsFiledTrendPct { get; set; }

    /// On-time rate, Day/Night shift only — replaces the old Calling-only
    /// "leads handled" card, which said nothing about the other three departments.
    public int PunctualityRatePct { get; set; }
    public int PunctualityRateTrendPct { get; set; }
    public List<RosterEntry> Roster { get; set; } = new();

    /// One roster per day in the selected period (week/month) — lets the web
    /// dashboard show the full period's breakdown, not just "today"'s single roster.
    public List<DayRosterDto> DailyBreakdown { get; set; } = new();

    /// See AdminDashboardDto.PushNotificationsEnabled — same "FCM silently
    /// disabled" visibility gap, same fix, for the web dashboard.
    public bool PushNotificationsEnabled { get; set; }
}
