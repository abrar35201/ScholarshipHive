using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers.Api;

/// JSON mirror of the web Admin panel so an Admin who signs into the mobile app gets
/// the same capabilities there, not just the Employee experience.
[ApiController]
[Route("api/admin")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Auditor,SuperAdmin,Owner,CountryHead")]
public class AdminController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IPasswordHasher<User> _hasher;
    private readonly RealtimeNotifier _realtime;
    private readonly NetworkAccessService _networkAccess;
    private readonly DashboardAnalyticsService _analytics;
    private readonly AnalyticsService _analyticsService;
    private readonly FcmPushService _fcm;
    private readonly AttendanceDurationService _duration;
    private readonly UserActiveStatusCache _activeCache;

    public AdminController(AppDbContext db, IPasswordHasher<User> hasher, RealtimeNotifier realtime, NetworkAccessService networkAccess, DashboardAnalyticsService analytics, AnalyticsService analyticsService, FcmPushService fcm, AttendanceDurationService duration, UserActiveStatusCache activeCache)
    {
        _db = db;
        _hasher = hasher;
        _realtime = realtime;
        _networkAccess = networkAccess;
        _analytics = analytics;
        _analyticsService = analyticsService;
        _fcm = fcm;
        _duration = duration;
        _activeCache = activeCache;
    }

    // ----- Hours (real accumulated presence duration, not just attendance) -----

    /// Every active employee's total accumulated presence over [from, to] — defaults to
    /// the last calendar month through today when either bound is omitted.
    [HttpGet("hours")]
    public async Task<ActionResult<List<HoursListEntryDto>>> Hours([FromQuery] DateOnly? from, [FromQuery] DateOnly? to)
    {
        var today = DateTimeExtensions.PakistanToday();
        var effectiveTo = to ?? today;
        var effectiveFrom = from ?? effectiveTo.AddMonths(-1);

        var employees = await _db.Users.Where(u => (u.Role != UserRole.Admin || u.Username.ToLower() != "admin")).OrderBy(u => u.FullName).ToListAsync();
        var byUser = await _duration.ComputeManyAsync(employees.Select(u => u.Id).ToList(), effectiveFrom, effectiveTo, DateTime.UtcNow);

        var result = employees.Select(u => new HoursListEntryDto
        {
            UserId = u.Id,
            Name = u.FullName,
            Department = u.Department.ToString(),
            TotalMinutes = byUser[u.Id].Values.Sum(d => d.Minutes),
            GapMinutes = byUser[u.Id].Values.Sum(d => d.GapMinutes)
        }).OrderByDescending(e => e.TotalMinutes).ToList();

        return Ok(result);
    }

    /// One person's day-by-day breakdown over [from, to] — an explicit range here
    /// overrides whatever default/global range the list page was showing.
    [HttpGet("hours/{id:int}")]
    public async Task<ActionResult<HoursDetailDto>> HoursDetail(int id, [FromQuery] DateOnly? from, [FromQuery] DateOnly? to)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (IsAuditor && user.Role == UserRole.Admin) return Forbid();

        var today = DateTimeExtensions.PakistanToday();
        var effectiveTo = to ?? today;
        var effectiveFrom = from ?? effectiveTo.AddMonths(-1);

        var byDay = await _duration.ComputeAsync(id, effectiveFrom, effectiveTo, DateTime.UtcNow);
        var days = new List<HoursDayDto>();
        for (var d = effectiveTo; d >= effectiveFrom; d = d.AddDays(-1))
        {
            var dur = byDay.GetValueOrDefault(d, new DayDuration(0, false));
            days.Add(new HoursDayDto { Date = d, Minutes = dur.Minutes, GapMinutes = dur.GapMinutes, StillOpen = dur.StillOpen });
        }

        return Ok(new HoursDetailDto
        {
            UserId = user.Id,
            Name = user.FullName,
            TotalMinutes = days.Sum(d => d.Minutes),
            TotalGapMinutes = days.Sum(d => d.GapMinutes),
            Days = days
        });
    }

    [HttpGet("dashboard")]
    public async Task<ActionResult<AdminDashboardDto>> Dashboard([FromQuery] string period = "day")
    {
        if (period is not ("day" or "week" or "month")) period = "day";
        var today = DateTimeExtensions.PakistanToday();
        var analytics = await _analytics.ComputeAsync(period);
        return Ok(new AdminDashboardDto
        {
            TotalUsers = await _db.Users.CountAsync(),
            CheckedInNow = analytics.CheckedInNow,
            ReportsToday = await _db.Attendances.CountAsync(a => a.Date == today && a.ReportSubmitted),
            ConfiguredRouters = await _db.AllowedRouters.CountAsync(r => r.IsActive),
            PendingApprovals = await _db.Users.CountAsync(u => !u.IsApproved),
            PendingNetworks = await _db.PendingNetworks.CountAsync(),
            WeeklyHeadcount = analytics.WeeklyHeadcount,
            ArrivalCurve = analytics.ArrivalCurve,
            PresentOnTimeToday = analytics.PresentOnTimeToday,
            LateToday = analytics.LateToday,
            AbsentToday = analytics.AbsentToday,
            ShiftHealth = analytics.ShiftHealth,
            TotalActiveEmployees = analytics.TotalActiveEmployees,
            AwayCount = analytics.AwayCount,
            AverageArrivalLabel = analytics.AverageArrivalLabel,
            AverageArrivalSublabel = analytics.AverageArrivalSublabel,
            AverageArrivalTrendMinutes = analytics.AverageArrivalTrendMinutes,
            ReportsFiledRate = analytics.ReportsFiledRate,
            ReportsFiledFraction = analytics.ReportsFiledFraction,
            ReportsFiledTrendPct = analytics.ReportsFiledTrendPct,
            PunctualityRatePct = analytics.PunctualityRatePct,
            PunctualityRateTrendPct = analytics.PunctualityRateTrendPct,
            Roster = analytics.Roster,
            DailyBreakdown = analytics.DailyBreakdown,
            PushNotificationsEnabled = _fcm.IsEnabled
        });
    }

    [HttpGet("analytics")]
    public async Task<ActionResult<AnalyticsData>> Analytics()
    {
        return Ok(await _analyticsService.ComputeAsync());
    }

    /// Rate/reports/punctuality per active employee, last 30 working days —
    /// powers the mobile Team tab's metric cards.
    [HttpGet("team-metrics")]
    public async Task<ActionResult<List<TeamMetricsEntry>>> TeamMetrics()
    {
        var users = await _db.Users.ToListAsync();
        var metrics = await _analyticsService.ComputeTeamMetricsAsync(users);
        return Ok(metrics.Values.ToList());
    }

    /// Office-wide attendance calendar + one day's full roster log — the
    /// mobile equivalent of the web Attendance page's office-wide mode.
    [HttpGet("attendance/office")]
    public async Task<ActionResult<OfficeAttendanceDto>> OfficeAttendance([FromQuery] DateOnly? date, [FromQuery] EmployeeDepartment? department)
    {
        var employees = await _db.Users.Where(u => (u.Role != UserRole.Admin || u.Username.ToLower() != "admin")).OrderBy(u => u.Username).ToListAsync();
        var selectedDate = date ?? DateTimeExtensions.PakistanToday();
        var (calendar, monthLabel, dayRoster, activeCount) = await _analyticsService.ComputeOfficeAttendanceAsync(selectedDate, department, employees);
        return Ok(new OfficeAttendanceDto
        {
            Calendar = calendar,
            MonthLabel = monthLabel,
            SelectedDate = selectedDate,
            DayRoster = dayRoster,
            ActiveEmployeeCount = activeCount
        });
    }

    // ----- Users -----

    // Auditors share the "Admin,Auditor" class-level policy for read/manage access to
    // this controller, but must never see Admin accounts or be able to grant the Admin
    // role — that stays exclusively an Admin action/visibility.
    private async Task<bool> IsPrimaryAdminActorAsync() =>
        int.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id) &&
        await _db.Users.AnyAsync(u => u.Id == id && u.Username.ToLower() == "admin" && u.Role == UserRole.Admin && u.IsActive);

    private UserRole CurrentRole => Enum.TryParse<UserRole>(User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value, out var r) ? r : UserRole.Employee;
    private bool IsAuditor => User.IsInRole(nameof(UserRole.Auditor));

    [HttpGet("users")]
    public async Task<ActionResult<List<AdminUserDto>>> Users()
    {
        var query = _db.Users.AsQueryable();
        if (IsAuditor)
        {
            query = query.Where(u => u.Role != UserRole.Admin);
        }
        var users = await query.OrderBy(u => u.IsApproved).ThenBy(u => u.Username).ToListAsync();

        var today = DateTimeExtensions.PakistanToday();
        var lastSeenByUser = await _db.Attendances
            .Where(a => a.Date == today)
            .ToDictionaryAsync(a => a.UserId, a => (DateTime?)a.LastPingAt);

        return Ok(users.Select(u => ToDto(u, lastSeenByUser.GetValueOrDefault(u.Id))).ToList());
    }

    /// Everything about one user in a single call — profile, attendance history,
    /// full login/checkin/logout event log, and their reports.
    [HttpGet("users/{id:int}/detail")]
    public async Task<ActionResult<AdminUserDetailDto>> UserDetail(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (IsAuditor && user.Role == UserRole.Admin) return Forbid();

        var attendance = await _db.Attendances
            .Where(a => a.UserId == id)
            .OrderByDescending(a => a.Date)
            .Take(100)
            .Select(a => new AdminAttendanceDto
            {
                Id = a.Id,
                UserId = id,
                Username = user.Username,
                Date = a.Date,
                CheckInTime = a.CheckInTime,
                CheckOutTime = a.CheckOutTime,
                ReportSubmitted = a.ReportSubmitted
            })
            .ToListAsync();

        var routerNames = await _networkAccess.GetRouterNameLookupAsync();
        var history = (await _db.LoginHistories
            .Where(h => h.UserId == id)
            .OrderByDescending(h => h.Timestamp)
            .Take(200)
            .ToListAsync())
            .Select(h => new LoginHistoryDto
            {
                Id = h.Id,
                EventType = h.EventType.ToString(),
                Timestamp = h.Timestamp,
                Bssid = h.Bssid,
                RouterName = h.Bssid is not null && routerNames.TryGetValue(NetworkAccessService.Normalize(h.Bssid), out var name) ? name : h.Bssid
            })
            .ToList();

        var reports = await _db.Reports
            .Include(r => r.Attendance)
            .Where(r => r.UserId == id)
            .OrderByDescending(r => r.Attendance!.Date)
            .Take(100)
            .Select(r => new AdminReportDto
            {
                Id = r.Id,
                Username = user.Username,
                Department = user.Department.ToString(),
                Date = r.Attendance!.Date,
                UnreadChats = r.UnreadChats,
                NewLeads = r.NewLeads,
                QualifiedLeads = r.QualifiedLeads,
                FollowUp = r.FollowUp,
                Calls = r.Calls,
                Potential = r.Potential,
                WalkIns = r.WalkIns,
                Conversion = r.Conversion,
                TextContent = r.TextContent,
                Files = r.Files.Select(f => new ReportFileResponse { Id = f.Id, FileName = f.FileName, UploadedAt = f.UploadedAt }).ToList(),
                SubmittedAt = r.SubmittedAt,
                LastEditedAt = r.LastEditedAt,
                CheckInTime = r.Attendance.CheckInTime,
                CheckOutTime = r.Attendance.CheckOutTime,
                ReviewStatus = r.ReviewStatus.ToString()
            })
            .ToListAsync();

        var today = DateTimeExtensions.PakistanToday();
        var todayDuration = await _duration.ComputeAsync(id, today, today, DateTime.UtcNow);
        var todayPresence = todayDuration.GetValueOrDefault(today, new DayDuration(0, false));

        return Ok(new AdminUserDetailDto
        {
            Profile = ToDto(user),
            Attendance = attendance,
            History = history,
            Reports = reports,
            TodayAccumulatedMinutes = todayPresence.Minutes,
            TodayStillOpen = todayPresence.StillOpen
        });
    }

    [HttpPost("users")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<ActionResult<AdminUserDto>> CreateUser([FromBody] AdminCreateUserRequest request)
    {
        if ((request.Role is (UserRole.HeadOfProcessing or UserRole.HeadOfCounselors or UserRole.HeadOfMarketing or UserRole.Owner or UserRole.CountryHead) && !await IsPrimaryAdminActorAsync()) ||
            request.Username.Trim().Equals("admin", StringComparison.OrdinalIgnoreCase) ||
            request.Role is UserRole.Admin or UserRole.SuperAdmin || !AccessRules.CanManageRole(CurrentRole, request.Role))
        {
            return BadRequest(new ApiError { Message = "Only an Admin can create an Admin account." });
        }

        if (request.Role == UserRole.Employee && !AccessRules.IsActualEmployeeDepartment(request.Department))
            return BadRequest(new ApiError { Message = "Choose a valid employee department." });
        var normalized = request.Username.Trim().ToLowerInvariant();
        if (await _db.Users.AnyAsync(u => u.Username.ToLower() == normalized))
        {
            return BadRequest(new ApiError { Message = "This username is already taken." });
        }

        var user = new User
        {
            Username = request.Username.Trim(),
            FullName = request.FullName.Trim(),
            Role = request.Role,
            Department = AccessRules.DepartmentScope(request.Role) ?? request.Department,
            IsActive = true,
            IsApproved = true
        };
        user.PasswordHash = _hasher.HashPassword(user, request.Password);

        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");
        return Ok(ToDto(user));
    }

    [HttpPut("users/{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<ActionResult<AdminUserDto>> EditUser(int id, [FromBody] AdminEditUserRequest request)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (!AccessRules.CanManageRole(CurrentRole, user.Role) || !AccessRules.CanManageRole(CurrentRole, request.Role)) return Forbid();
        if (user.Role is (UserRole.HeadOfProcessing or UserRole.HeadOfCounselors or UserRole.HeadOfMarketing or UserRole.Owner or UserRole.CountryHead) && !await IsPrimaryAdminActorAsync()) return Forbid();
        if (request.Role is (UserRole.HeadOfProcessing or UserRole.HeadOfCounselors or UserRole.HeadOfMarketing or UserRole.Owner or UserRole.CountryHead) && request.Role != user.Role && !await IsPrimaryAdminActorAsync()) return Forbid();
        if (AccessRules.IsPrimaryAdmin(user))
        {
            if (!await IsPrimaryAdminActorAsync() || request.Role != UserRole.Admin || !request.IsActive || !request.IsApproved ||
                !request.Username.Trim().Equals("admin", StringComparison.OrdinalIgnoreCase)) return Forbid();
        }
        else if (user.Role == UserRole.Admin || request.Role == UserRole.Admin ||
                 request.Role == UserRole.SuperAdmin || request.Username.Trim().Equals("admin", StringComparison.OrdinalIgnoreCase)) return Forbid();

        var normalized = request.Username.Trim().ToLowerInvariant();
        if (await _db.Users.AnyAsync(u => u.Username.ToLower() == normalized && u.Id != id))
        {
            return BadRequest(new ApiError { Message = "This username is already taken." });
        }

        user.Username = request.Username.Trim();
        user.FullName = request.FullName.Trim();
        user.Role = request.Role;
        user.Department = AccessRules.DepartmentScope(request.Role) ?? request.Department;
        user.IsActive = request.IsActive;
        user.IsApproved = request.IsApproved;
        user.FailedLoginAttempts = 0;
        user.LockedUntil = null;

        if (!string.IsNullOrWhiteSpace(request.Password))
        {
            user.PasswordHash = _hasher.HashPassword(user, request.Password);
        }

        await _db.SaveChangesAsync();
        _activeCache.Invalidate(user.Id);
        await _realtime.NotifyAsync("users");
        return Ok(ToDto(user));
    }

    /// One person's shift — the mobile Shifts screen's per-row Save action.
    public sealed class MarketingAdminAccessRequest { public bool Enabled { get; set; } }

    [HttpPost("users/{id:int}/marketing-admin")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> SetMarketingAdmin(int id, [FromBody] MarketingAdminAccessRequest request)
    {
        if (!await IsPrimaryAdminActorAsync()) return Forbid();
        var target = await _db.Users.FindAsync(id);
        if (target == null) return NotFound();
        if (AccessRules.IsPrimaryAdmin(target) ||
            target.Role is not (UserRole.Employee or UserRole.HeadOfMarketing or UserRole.Admin) ||
            target.Department != EmployeeDepartment.Marketing) return BadRequest(new { message = "Target must be a Marketing Head." });
        if (request.Enabled && target.Role != UserRole.Employee) return BadRequest(new { message = "Already has admin access." });
        if (!request.Enabled && target.Role is not (UserRole.Admin or UserRole.HeadOfMarketing)) return BadRequest(new { message = "No admin access to revoke." });
        target.Role = request.Enabled ? UserRole.HeadOfMarketing : UserRole.Employee;
        await _db.SaveChangesAsync();
        _activeCache.Invalidate(target.Id);
        await _realtime.NotifyAsync("users");
        return Ok(new { message = request.Enabled ? "Admin access granted." : "Admin access revoked." });
    }

    [HttpPost("users/{id:int}/reset-device")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> ResetDevice(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (!AccessRules.CanManageRole(CurrentRole, user.Role) || AccessRules.IsPrimaryAdmin(user)) return Forbid();
        user.HomeDeviceId = null; user.LastDeviceId = null; user.LastDeviceLoginAt = null; user.FcmToken = null;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");
        return Ok(new { message = "Device reset. Employee must sign in with password on their phone." });
    }

    [HttpPut("users/{id:int}/shift")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<ActionResult<AdminUserDto>> SetShift(int id, [FromBody] SetShiftRequest request)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (IsAuditor && user.Role == UserRole.Admin) return Forbid();

        user.ShiftStartTime = request.ShiftStartTime;
        user.ShiftEndTime = request.ShiftEndTime;
        user.ShiftType = request.ShiftType;
        _db.UserNotices.Add(new UserNotice { UserId=user.Id, Title="Your shift was updated",
            Body=$"Your new {request.ShiftType} shift is {request.ShiftStartTime:HH:mm}–{request.ShiftEndTime:HH:mm}.",
            ActorName=User.Identity?.Name ?? "Administrator" });
        await _db.SaveChangesAsync();
        if (!string.IsNullOrWhiteSpace(user.FcmToken)) await _fcm.SendNotificationAsync(user.FcmToken, "Shift timing changed", $"New shift: {request.ShiftStartTime:HH:mm}–{request.ShiftEndTime:HH:mm}");
        await _realtime.NotifyAsync("users");
        return Ok(ToDto(user));
    }

    /// Bulk-set a shift — either every active employee in Department, or
    /// (when UserIds is non-empty) exactly those people regardless of
    /// department. An explicit UserIds selection always wins over Department.
    [HttpPost("users/shift/bulk")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<ActionResult<List<AdminUserDto>>> SetShiftBulk([FromBody] SetShiftRequest request)
    {
        var query = _db.Users.Where(u => u.Role == UserRole.Employee).AsQueryable();
        query = request.UserIds.Count > 0
            ? query.Where(u => request.UserIds.Contains(u.Id))
            : request.Department.HasValue
                ? query.Where(u => u.Department == request.Department.Value)
                : query;

        var affected = await query.ToListAsync();
        foreach (var u in affected)
        {
            u.ShiftStartTime = request.ShiftStartTime;
            u.ShiftEndTime = request.ShiftEndTime;
            u.ShiftType = request.ShiftType;
            _db.UserNotices.Add(new UserNotice { UserId=u.Id, Title="Your shift was updated",
                Body=$"Your new {request.ShiftType} shift is {request.ShiftStartTime:HH:mm}–{request.ShiftEndTime:HH:mm}.",
                ActorName=User.Identity?.Name ?? "Administrator" });
        }
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");
        foreach (var u in affected.Where(x => !string.IsNullOrWhiteSpace(x.FcmToken)))
            await _fcm.SendNotificationAsync(u.FcmToken!, "Shift timing changed", $"New shift: {request.ShiftStartTime:HH:mm}–{request.ShiftEndTime:HH:mm}");
        return Ok(affected.Select(u => ToDto(u)).ToList());
    }

    [HttpPost("users/{id:int}/approve")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> ApproveUser(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (IsAuditor && user.Role == UserRole.Admin) return Forbid();
        user.IsApproved = true;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");
        return Ok(ToDto(user));
    }

    [HttpDelete("users/{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> DeleteUser(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is not null && IsAuditor && user.Role == UserRole.Admin) return Forbid();
        if (user is not null)
        {
            if (AccessRules.IsPrimaryAdmin(user) || !AccessRules.CanManageRole(CurrentRole, user.Role) ||
                (user.Role is (UserRole.Admin or UserRole.HeadOfMarketing or UserRole.HeadOfProcessing or UserRole.HeadOfCounselors) && !await IsPrimaryAdminActorAsync())) return Forbid();
        _db.Users.Remove(user);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("users");
        }
        return Ok(new { message = "Deleted." });
    }

    // ----- Attendance -----

    [HttpGet("attendance")]
    public async Task<ActionResult<List<AdminAttendanceDto>>> Attendance([FromQuery] int? userId, [FromQuery] DateOnly? date)
    {
        var query = _db.Attendances.Include(a => a.User).AsQueryable();
        if (userId.HasValue) query = query.Where(a => a.UserId == userId.Value);
        if (date.HasValue) query = query.Where(a => a.Date == date.Value);

        var records = await query
            .OrderByDescending(a => a.Date).ThenByDescending(a => a.CheckInTime)
            .Take(200)
            .Select(a => new AdminAttendanceDto
            {
                Id = a.Id,
                UserId = a.UserId,
                Username = a.User!.Username,
                Date = a.Date,
                CheckInTime = a.CheckInTime,
                CheckOutTime = a.CheckOutTime,
                ReportSubmitted = a.ReportSubmitted
            })
            .ToListAsync();

        return Ok(records);
    }

    // ----- Reports -----

    /// Admin/Auditor can view any date range for any user — unlike the employee's
    /// own "mine" view (see ReportsController.Mine), which is capped to the last
    /// month. Omitting both dates defaults to just today; omitting only one
    /// treats the range as that single day.
    [HttpGet("reports")]
    public async Task<ActionResult<List<AdminReportDto>>> Reports([FromQuery] int? userId, [FromQuery] DateOnly? fromDate, [FromQuery] DateOnly? toDate)
    {
        var query = _db.Reports.Include(r => r.User).Include(r => r.Attendance).Include(r => r.Files).AsQueryable();
        if (userId.HasValue) query = query.Where(r => r.UserId == userId.Value);

        // Filters by the day the report is FOR (its Attendance date), not when it was
        // first submitted — an edited-later-that-day report still belongs to that day.
        var effectiveFrom = fromDate ?? toDate ?? DateTimeExtensions.PakistanToday();
        var effectiveTo = toDate ?? fromDate ?? DateTimeExtensions.PakistanToday();
        query = query.Where(r => r.Attendance!.Date >= effectiveFrom && r.Attendance!.Date <= effectiveTo);

        var reports = await query
            .OrderByDescending(r => r.Attendance!.Date)
            .ThenBy(r => r.User!.Username)
            .Take(2000)
            .Select(r => new AdminReportDto
            {
                Id = r.Id,
                Username = r.User!.Username,
                Department = r.User!.Department.ToString(),
                Date = r.Attendance!.Date,
                UnreadChats = r.UnreadChats,
                NewLeads = r.NewLeads,
                QualifiedLeads = r.QualifiedLeads,
                FollowUp = r.FollowUp,
                Calls = r.Calls,
                Potential = r.Potential,
                WalkIns = r.WalkIns,
                Conversion = r.Conversion,
                TextContent = r.TextContent,
                Files = r.Files.Select(f => new ReportFileResponse { Id = f.Id, FileName = f.FileName, UploadedAt = f.UploadedAt }).ToList(),
                SubmittedAt = r.SubmittedAt,
                LastEditedAt = r.LastEditedAt,
                CheckInTime = r.Attendance.CheckInTime,
                CheckOutTime = r.Attendance.CheckOutTime,
                ReviewStatus = r.ReviewStatus.ToString()
            })
            .ToListAsync();

        return Ok(reports);
    }

    /// Lets an Admin open/download any file an employee attached to a report.
    [HttpGet("reports/files/{id:int}")]
    public async Task<IActionResult> DownloadReportFile(int id)
    {
        var file = await _db.ReportFiles.FindAsync(id);
        if (file is null)
        {
            return NotFound();
        }

        return File(file.FileData, file.ContentType ?? "application/octet-stream", file.FileName);
    }

    /// Mobile equivalent of the web Reports page's Sign off / Ask for more
    /// detail / Flag actions — same review workflow, same real FCM push.
    [HttpPost("reports/{id:int}/sign-off")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> SignOffReport(int id)
    {
        var report = await _db.Reports.FindAsync(id);
        if (report is null) return NotFound();
        report.ReviewStatus = ReportReviewStatus.SignedOff;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("reports");
        return Ok(new { message = "Signed off." });
    }

    [HttpPost("reports/{id:int}/flag")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> FlagReport(int id)
    {
        var report = await _db.Reports.FindAsync(id);
        if (report is null) return NotFound();
        report.ReviewStatus = ReportReviewStatus.Flagged;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("reports");
        return Ok(new { message = "Flagged." });
    }

    [HttpPost("reports/{id:int}/ask-for-detail")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> AskForDetailReport(int id)
    {
        var report = await _db.Reports.Include(r => r.User).Include(r => r.Attendance).FirstOrDefaultAsync(r => r.Id == id);
        if (report is null) return NotFound();

        report.ReviewStatus = ReportReviewStatus.NeedsMoreDetail;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("reports");

        if (!string.IsNullOrWhiteSpace(report.User?.FcmToken))
        {
            await _fcm.SendNotificationAsync(
                report.User.FcmToken,
                "More detail requested",
                $"An admin asked for more detail on your {report.Attendance?.Date:MMM d} report.");
        }
        return Ok(new { message = "Requested." });
    }

    // ----- Routers ----- (Admin only — Auditor doesn't get network configuration access)

    [HttpGet("routers")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<List<AdminRouterDto>>> Routers()
    {
        var routers = await _db.AllowedRouters.OrderByDescending(r => r.CreatedAt).ToListAsync();
        return Ok(routers.Select(r => new AdminRouterDto
        {
            Id = r.Id,
            Name = r.Name,
            Bssid = r.Bssid,
            IsActive = r.IsActive,
            CreatedAt = r.CreatedAt
        }).ToList());
    }

    [HttpPost("routers")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> AddRouter([FromBody] AdminAddRouterRequest request)
    {
        var bssid = NetworkAccessService.Normalize(request.Bssid);
        var existingBssids = await _db.AllowedRouters.Select(r => r.Bssid).ToListAsync();
        if (existingBssids.Any(existing => NetworkAccessService.Normalize(existing) == bssid))
        {
            return BadRequest(new ApiError { Message = "This BSSID is already added." });
        }

        _db.AllowedRouters.Add(new AllowedRouter
        {
            Name = request.Name.Trim(),
            Bssid = bssid,
            IsActive = request.IsActive
        });
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("network");
        return Ok(new { message = "Router added." });
    }

    [HttpPut("routers/{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> EditRouter(int id, [FromBody] AdminAddRouterRequest request)
    {
        var router = await _db.AllowedRouters.FindAsync(id);
        if (router is null) return NotFound();

        router.Name = request.Name.Trim();
        var bssid = NetworkAccessService.Normalize(request.Bssid);
        var existingBssids = await _db.AllowedRouters
            .Where(r => r.Id != router.Id)
            .Select(r => r.Bssid)
            .ToListAsync();
        if (existingBssids.Any(existing => NetworkAccessService.Normalize(existing) == bssid))
        {
            return BadRequest(new ApiError { Message = "This BSSID is already added." });
        }

        router.Bssid = bssid;
        router.IsActive = request.IsActive;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("network");
        return Ok(new { message = "Router updated." });
    }

    [HttpDelete("routers/{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteRouter(int id)
    {
        var router = await _db.AllowedRouters.FindAsync(id);
        if (router is not null)
        {
            _db.AllowedRouters.Remove(router);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("network");
        }
        return Ok(new { message = "Deleted." });
    }

    // ----- Geofenced locations ----- (Admin only) — wakes the mobile app's
    // attendance service on arrival/departure; AllowedRouter stays the actual
    // attendance verification.

    [HttpGet("locations")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<List<AdminLocationDto>>> Locations()
    {
        var locations = await _db.AllowedLocations.OrderByDescending(l => l.CreatedAt).ToListAsync();
        return Ok(locations.Select(l => new AdminLocationDto
        {
            Id = l.Id,
            Name = l.Name,
            Latitude = l.Latitude,
            Longitude = l.Longitude,
            RadiusMeters = l.RadiusMeters,
            IsActive = l.IsActive,
            CreatedAt = l.CreatedAt
        }).ToList());
    }

    [HttpPost("locations")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> AddLocation([FromBody] AdminAddLocationRequest request)
    {
        _db.AllowedLocations.Add(new AllowedLocation
        {
            Name = request.Name.Trim(),
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            RadiusMeters = request.RadiusMeters,
            IsActive = request.IsActive
        });
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("network");
        return Ok(new { message = "Location added." });
    }

    [HttpPut("locations/{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> EditLocation(int id, [FromBody] AdminAddLocationRequest request)
    {
        var location = await _db.AllowedLocations.FindAsync(id);
        if (location is null) return NotFound();

        location.Name = request.Name.Trim();
        location.Latitude = request.Latitude;
        location.Longitude = request.Longitude;
        location.RadiusMeters = request.RadiusMeters;
        location.IsActive = request.IsActive;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("network");
        return Ok(new { message = "Location updated." });
    }

    [HttpDelete("locations/{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteLocation(int id)
    {
        var location = await _db.AllowedLocations.FindAsync(id);
        if (location is not null)
        {
            _db.AllowedLocations.Remove(location);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("network");
        }
        return Ok(new { message = "Deleted." });
    }

    // ----- Pending networks ----- (Admin only)

    [HttpGet("pending-networks")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<List<AdminPendingNetworkDto>>> PendingNetworks()
    {
        var pending = await _db.PendingNetworks.OrderByDescending(p => p.LastSeenAt).ToListAsync();
        return Ok(pending.Select(p => new AdminPendingNetworkDto
        {
            Id = p.Id,
            Bssid = p.Bssid,
            Ssid = p.Ssid,
            LastSeenFromIp = p.LastSeenFromIp,
            AttemptCount = p.AttemptCount,
            FirstSeenAt = p.FirstSeenAt,
            LastSeenAt = p.LastSeenAt
        }).ToList());
    }

    [HttpPost("pending-networks/{id:int}/approve")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> ApprovePendingNetwork(int id)
    {
        var pending = await _db.PendingNetworks.FindAsync(id);
        if (pending is null) return NotFound();

        var bssid = NetworkAccessService.Normalize(pending.Bssid);
        var existingBssids = await _db.AllowedRouters.Select(r => r.Bssid).ToListAsync();
        if (!existingBssids.Any(existing => NetworkAccessService.Normalize(existing) == bssid))
        {
            _db.AllowedRouters.Add(new AllowedRouter
            {
                Name = string.IsNullOrWhiteSpace(pending.Ssid) ? bssid : pending.Ssid,
                Bssid = bssid,
                IsActive = true
            });
        }
        _db.PendingNetworks.Remove(pending);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("network");
        return Ok(new { message = "Approved." });
    }

    [HttpDelete("pending-networks/{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DismissPendingNetwork(int id)
    {
        var pending = await _db.PendingNetworks.FindAsync(id);
        if (pending is not null)
        {
            _db.PendingNetworks.Remove(pending);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("network");
        }
        return Ok(new { message = "Dismissed." });
    }

    // ----- Password reset requests ----- (Admin only — same sensitivity as setting
    // someone's password directly via EditUser)

    [HttpGet("password-resets")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<List<PendingPasswordResetDto>>> PasswordResets()
    {
        var pending = await _db.PendingPasswordResets
            .Include(p => p.User)
            .OrderBy(p => p.RequestedAt)
            .ToListAsync();

        return Ok(pending.Select(p => new PendingPasswordResetDto
        {
            Id = p.Id,
            UserId = p.UserId,
            UserName = p.User?.FullName.Length > 0 ? p.User!.FullName : p.User?.Username ?? "?",
            RequestedAt = p.RequestedAt,
            DeviceRecognized = p.DeviceRecognized
        }).ToList());
    }

    [HttpPost("password-resets/{id:int}/approve")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> ApprovePasswordReset(int id)
    {
        var pending = await _db.PendingPasswordResets.Include(p => p.User).FirstOrDefaultAsync(p => p.Id == id);
        if (pending is null) return NotFound();
        var user = pending.User;
        if (user is null) return NotFound();

        user.PasswordHash = pending.NewPasswordHash;
        user.FailedLoginAttempts = 0;
        user.LockedUntil = null;
        _db.PendingPasswordResets.Remove(pending);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("password-resets");

        // Store-and-forward via FCM: delivers whenever this device is next online,
        // whether or not the employee is checked in or even has the app open right
        // now — exactly the "first checked-in device after this action" guarantee
        // the reset flow promises.
        if (!string.IsNullOrWhiteSpace(user.FcmToken))
        {
            await _fcm.SendNotificationAsync(
                user.FcmToken,
                "Password updated",
                "Your password was updated. You can now log in with your new password.");
        }

        return Ok(new { message = "Password updated." });
    }

    [HttpPost("password-resets/{id:int}/reject")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> RejectPasswordReset(int id)
    {
        var pending = await _db.PendingPasswordResets.FindAsync(id);
        if (pending is not null)
        {
            _db.PendingPasswordResets.Remove(pending);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("password-resets");
        }
        return Ok(new { message = "Dismissed." });
    }

    private static AdminUserDto ToDto(User user, DateTime? lastSeenAt = null) => new()
    {
        Id = user.Id,
        Username = user.Username,
        FullName = user.FullName,
        Role = user.Role.ToString(),
        Department = user.Department.ToString(),
        IsActive = user.IsActive,
        IsApproved = user.IsApproved,
        IsLocked = user.LockedUntil is not null && user.LockedUntil > DateTime.UtcNow,
        CreatedAt = user.CreatedAt,
        ShiftStartTime = user.ShiftStartTime,
        ShiftEndTime = user.ShiftEndTime,
        ShiftType = user.ShiftType.ToString(),
        LastSeenAt = lastSeenAt
    };
}
