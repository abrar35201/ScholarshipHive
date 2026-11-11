using System.ComponentModel.DataAnnotations;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Dtos;

// JSON DTOs for the mobile admin experience (/api/admin/...). Kept separate from the
// Razor ViewModels above since these are serialized directly, not bound from forms.

public class AdminDashboardDto
{
    public int TotalUsers { get; set; }
    public int CheckedInNow { get; set; }
    public int ReportsToday { get; set; }
    public int ConfiguredRouters { get; set; }
    public int PendingApprovals { get; set; }
    public int PendingNetworks { get; set; }

    public List<ChartPoint> WeeklyHeadcount { get; set; } = new();
    public List<ChartPoint> ArrivalCurve { get; set; } = new();
    public int PresentOnTimeToday { get; set; }
    public int LateToday { get; set; }
    public int AbsentToday { get; set; }

    /// Day/Night shift breakdown — see ShiftHealth's doc comment for why
    /// Internship shift (the interns) is left out of this.
    public List<ShiftHealth> ShiftHealth { get; set; } = new();

    public int TotalActiveEmployees { get; set; }
    public int AwayCount { get; set; }
    public string AverageArrivalLabel { get; set; } = "—";
    public string AverageArrivalSublabel { get; set; } = "";
    public int AverageArrivalTrendMinutes { get; set; }
    public int ReportsFiledRate { get; set; }
    public string ReportsFiledFraction { get; set; } = "0 of 0";
    public int ReportsFiledTrendPct { get; set; }

    /// On-time rate, Day/Night shift only (see ShiftHealth) — replaces the old
    /// Calling-only "leads handled" card, which said nothing about the other
    /// three departments.
    public int PunctualityRatePct { get; set; }
    public int PunctualityRateTrendPct { get; set; }
    public List<RosterEntry> Roster { get; set; } = new();

    /// One entry per day in the selected period (Week/Month) — empty for
    /// "day", since the Roster above already covers that single day. Lets
    /// the mobile dashboard show a real day-by-day breakdown instead of only
    /// aggregate charts when a wider period is selected.
    public List<DayRosterDto> DailyBreakdown { get; set; } = new();

    /// False whenever FcmPushService couldn't initialize (missing/invalid
    /// Firebase:ServiceAccountJson) — previously a silent failure visible only
    /// in server logs, so a broken/expired credential could sit unnoticed for
    /// weeks with nothing but "why is nobody auto-checking-in today" as the
    /// symptom. The FCM wake ping (see FcmWakeService) is what lets a device
    /// recover from a missed geofence transition or an OEM-killed background
    /// process without anyone opening the app — with this off, that entire
    /// safety net is dark.
    public bool PushNotificationsEnabled { get; set; }
}

public class DayRosterDto
{
    public DateOnly Date { get; set; }
    public string DateLabel { get; set; } = string.Empty;
    public List<RosterEntry> Roster { get; set; } = new();
}

public class AdminUserDto
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public bool IsApproved { get; set; }
    public bool IsLocked { get; set; }
    public DateTime CreatedAt { get; set; }
    public TimeOnly ShiftStartTime { get; set; }
    public TimeOnly ShiftEndTime { get; set; }
    public string ShiftType { get; set; } = string.Empty;

    /// Today's Attendance.LastPingAt for this person, if any — the only way an
    /// admin can actually tell "this phone's background monitoring has gone
    /// quiet" instead of just guessing. Null means no attendance recorded yet
    /// today at all (never arrived, or hasn't reported in even once).
    public DateTime? LastSeenAt { get; set; }
}

/// One person's shift, or a bulk assignment — either Department or UserIds
/// is set (never both meaningfully), matching the web Shifts page's two
/// apply actions. An explicit UserIds selection always wins over Department
/// when both are present.
public class SetShiftRequest
{
    public List<int> UserIds { get; set; } = new();
    public EmployeeDepartment? Department { get; set; }
    public TimeOnly ShiftStartTime { get; set; }
    public TimeOnly ShiftEndTime { get; set; }
    public ShiftType ShiftType { get; set; }
}

public class AdminCreateUserRequest
{
    [Required, MaxLength(50)]
    public string Username { get; set; } = string.Empty;

    [MaxLength(100)]
    public string FullName { get; set; } = string.Empty;

    [Required, StrongPassword]
    public string Password { get; set; } = string.Empty;

    public UserRole Role { get; set; } = UserRole.Employee;
    public EmployeeDepartment Department { get; set; } = EmployeeDepartment.Calling;
}

public class AdminEditUserRequest
{
    [Required, MaxLength(50)]
    public string Username { get; set; } = string.Empty;

    [MaxLength(100)]
    public string FullName { get; set; } = string.Empty;

    [StrongPassword]
    public string? Password { get; set; }

    public UserRole Role { get; set; } = UserRole.Employee;
    public EmployeeDepartment Department { get; set; } = EmployeeDepartment.Calling;
    public bool IsActive { get; set; } = true;
    public bool IsApproved { get; set; } = true;
}

public class AdminAttendanceDto
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public DateOnly Date { get; set; }
    public DateTime CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    public bool ReportSubmitted { get; set; }
}

public class AdminReportDto
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public DateOnly Date { get; set; }
    public int UnreadChats { get; set; }
    public int NewLeads { get; set; }
    public int QualifiedLeads { get; set; }
    public int FollowUp { get; set; }
    public int Calls { get; set; }
    public int Potential { get; set; }
    public int WalkIns { get; set; }
    public int Conversion { get; set; }
    public string? TextContent { get; set; }
    public List<ReportFileResponse> Files { get; set; } = new();
    public DateTime SubmittedAt { get; set; }
    public DateTime? LastEditedAt { get; set; }
    public DateTime CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    public string ReviewStatus { get; set; } = "New";
}

public class OfficeAttendanceDto
{
    public List<CalendarDay> Calendar { get; set; } = new();
    public string MonthLabel { get; set; } = string.Empty;
    public DateOnly SelectedDate { get; set; }
    public List<AttendanceRosterRow> DayRoster { get; set; } = new();
    public int ActiveEmployeeCount { get; set; }
}

public class AdminRouterDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Bssid { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class AdminAddRouterRequest
{
    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Required, MaxLength(17)]
    [RegularExpression(@"^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$", ErrorMessage = "Enter a valid MAC address, e.g. AA:BB:CC:DD:EE:FF")]
    public string Bssid { get; set; } = string.Empty;

    public bool IsActive { get; set; } = true;
}

public class AdminLocationDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double RadiusMeters { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class AdminAddLocationRequest
{
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

public class LoginHistoryDto
{
    public int Id { get; set; }
    public string EventType { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string? Bssid { get; set; }
    public string? RouterName { get; set; }
}

/// Everything about one user in a single response — profile, attendance, full
/// login/checkin/logout history, and their submitted reports — so an admin can see
/// the complete picture from one tile without having to jump between screens.
public class AdminUserDetailDto
{
    public AdminUserDto Profile { get; set; } = new();
    public List<AdminAttendanceDto> Attendance { get; set; } = new();
    public List<LoginHistoryDto> History { get; set; } = new();
    public List<AdminReportDto> Reports { get; set; } = new();

    /// Real accumulated presence today (see AttendanceDurationService) — pairs every
    /// CheckIn/CheckOut cycle so far, so it's already paused for any gap since the
    /// last checkout and picks back up exactly where it left off on the next one.
    /// This admin view is the only place this now shows at all — the employee's own
    /// app no longer surfaces a live shift-progress readout of their own.
    public int TodayAccumulatedMinutes { get; set; }

    /// True while today's most recent cycle is still open (no checkout yet) — the
    /// admin UI's cue to keep ticking this forward locally instead of treating it as
    /// a final, paused total.
    public bool TodayStillOpen { get; set; }
}

public class AdminPendingNetworkDto
{
    public int Id { get; set; }
    public string Bssid { get; set; } = string.Empty;
    public string? Ssid { get; set; }
    public string? LastSeenFromIp { get; set; }
    public int AttemptCount { get; set; }
    public DateTime FirstSeenAt { get; set; }
    public DateTime LastSeenAt { get; set; }
}
