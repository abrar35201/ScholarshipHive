using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnly")]
public class UsersController : Controller
{
    private readonly AppDbContext _db;
    private readonly IPasswordHasher<User> _hasher;
    private readonly RealtimeNotifier _realtime;
    private readonly NetworkAccessService _networkAccess;
    private readonly AnalyticsService _analyticsService;
    private readonly FcmPushService _fcm;
    private readonly UserActiveStatusCache _activeCache;

    public UsersController(AppDbContext db, IPasswordHasher<User> hasher, RealtimeNotifier realtime, NetworkAccessService networkAccess, AnalyticsService analyticsService, FcmPushService fcm, UserActiveStatusCache activeCache)
    {
        _db = db;
        _hasher = hasher;
        _realtime = realtime;
        _networkAccess = networkAccess;
        _analyticsService = analyticsService;
        _fcm = fcm;
        _activeCache = activeCache;
    }

    // Auditors have broad read/manage access to this panel but must never see Admin
    // accounts or be able to grant the Admin role — that stays exclusively an Admin
    // action/visibility, even though both roles share the "AdminOnly" policy.
    private UserRole CurrentRole => Enum.TryParse<UserRole>(User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value, out var r) ? r : UserRole.Employee;
    private bool IsAuditor => User.IsInRole(nameof(UserRole.Auditor));
    private async Task<bool> IsPrimaryAdminActorAsync() =>
        int.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id) &&
        await _db.Users.AnyAsync(u => u.Id == id && u.Username.ToLower() == "admin" && u.Role == UserRole.Admin && u.IsActive);


    public async Task<IActionResult> Index(string? q, EmployeeDepartment? department)
    {
        var query = _db.Users.AsQueryable();
        if (IsAuditor)
        {
            query = query.Where(u => u.Role != UserRole.Admin);
        }
        if (!string.IsNullOrWhiteSpace(q))
        {
            query = query.Where(u => u.Username.Contains(q) || u.FullName.Contains(q));
        }
        var users = await query.OrderBy(u => u.IsApproved).ThenBy(u => u.Username).ToListAsync();
        ViewBag.SearchQuery = q;
        ViewBag.SelectedDepartment = department;
        ViewBag.Metrics = await _analyticsService.ComputeTeamMetricsAsync(users);
        ViewBag.PendingPasswordResets = await _db.PendingPasswordResets
            .Include(p => p.User)
            .OrderBy(p => p.RequestedAt)
            .ToListAsync();
        return View(users);
    }

    /// Shows one user's attendance, one row per day — click a day to drill into that
    /// day's full check-in/check-out timeline (see DayHistory).
    public async Task<IActionResult> Details(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (IsAuditor && user.Role == UserRole.Admin) return Forbid();

        var attendance = await _db.Attendances
            .Where(a => a.UserId == id)
            .OrderByDescending(a => a.Date)
            .Take(60)
            .ToListAsync();

        ViewBag.Attendance = attendance;
        return View(user);
    }

    /// One user's complete check-in/check-out timeline for a single day, paired into
    /// Check-In / Check-Out rows (they always alternate) with router names instead of
    /// bare BSSIDs.
    public async Task<IActionResult> DayHistory(int id, DateOnly date)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (IsAuditor && user.Role == UserRole.Admin) return Forbid();

        // The day's events are stored as UTC timestamps but the day boundary is Pakistan
        // local time (see DateTimeExtensions.PakistanToday — 7 AM rollover, UTC+5 offset,
        // so the boundary sits at 02:00 UTC = rollover(7) - offset(5) hours past midnight)
        // — convert the requested Pakistan calendar day to its UTC window. DateOnly.
        // ToDateTime always produces Kind=Unspecified, which Npgsql rejects for a
        // "timestamp with time zone" column — it must be explicitly marked Utc.
        var dayStartUtc = DateTime.SpecifyKind(date.ToDateTime(TimeOnly.MinValue).AddHours(2), DateTimeKind.Utc);
        var dayEndUtc = DateTime.SpecifyKind(date.AddDays(1).ToDateTime(TimeOnly.MinValue).AddHours(2), DateTimeKind.Utc);

        var events = await _db.LoginHistories
            .Where(h => h.UserId == id && h.Timestamp >= dayStartUtc && h.Timestamp < dayEndUtc)
            .OrderBy(h => h.Timestamp)
            .ToListAsync();

        var routerNames = await _networkAccess.GetRouterNameLookupAsync();

        var cycles = new List<CheckCycle>();
        LoginHistory? pendingCheckIn = null;
        foreach (var e in events)
        {
            if (e.EventType == LoginHistoryEvent.CheckIn)
            {
                if (pendingCheckIn is not null)
                {
                    // Two check-ins with no check-out between them shouldn't happen, but
                    // if it does, don't silently drop the earlier one.
                    cycles.Add(new CheckCycle { CheckIn = pendingCheckIn, RouterName = ResolveRouterName(pendingCheckIn.Bssid, routerNames) });
                }
                pendingCheckIn = e;
            }
            else
            {
                cycles.Add(new CheckCycle
                {
                    CheckIn = pendingCheckIn,
                    CheckOut = e,
                    RouterName = ResolveRouterName(e.Bssid ?? pendingCheckIn?.Bssid, routerNames)
                });
                pendingCheckIn = null;
            }
        }
        if (pendingCheckIn is not null)
        {
            cycles.Add(new CheckCycle { CheckIn = pendingCheckIn, RouterName = ResolveRouterName(pendingCheckIn.Bssid, routerNames) });
        }
        cycles.Reverse(); // most recent cycle first

        ViewBag.User = user;
        ViewBag.Date = date;
        return View(cycles);
    }

    private static string ResolveRouterName(string? bssid, Dictionary<string, string> routerNames)
    {
        if (string.IsNullOrWhiteSpace(bssid)) return "—";
        return routerNames.TryGetValue(NetworkAccessService.Normalize(bssid), out var name) ? name : bssid;
    }

    public class CheckCycle
    {
        public LoginHistory? CheckIn { get; set; }
        public LoginHistory? CheckOut { get; set; }
        public string RouterName { get; set; } = "—";
    }

    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public IActionResult Create() => View(new UserFormViewModel());

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> Create(UserFormViewModel model)
    {
        if (model.Username.Trim().Equals("admin", StringComparison.OrdinalIgnoreCase) ||
            model.Role is UserRole.Admin or UserRole.SuperAdmin || !AccessRules.CanManageRole(CurrentRole, model.Role))
        {
            ModelState.AddModelError(nameof(model.Role), "Only an Admin can create an Admin account.");
        }

        if (model.Role is (UserRole.HeadOfProcessing or UserRole.HeadOfCounselors or UserRole.HeadOfMarketing or UserRole.Owner or UserRole.CountryHead) && !await IsPrimaryAdminActorAsync())
            ModelState.AddModelError(nameof(model.Role), "Only the original admin can appoint a Head of Processing.");

        if (model.Role == UserRole.Employee && !AccessRules.IsActualEmployeeDepartment(model.Department))
            ModelState.AddModelError(nameof(model.Department), "Select a real employee department.");
        if (string.IsNullOrWhiteSpace(model.Password))
        {
            ModelState.AddModelError(nameof(model.Password), "Password is required for a new user.");
        }

        var normalizedUsername = model.Username.Trim().ToLowerInvariant();
        if (await _db.Users.AnyAsync(u => u.Username.ToLower() == normalizedUsername))
        {
            ModelState.AddModelError(nameof(model.Username), "This username is already taken.");
        }

        if (!ModelState.IsValid)
        {
            return View(model);
        }

        var user = new User
        {
            Username = model.Username.Trim(),
            FullName = model.FullName,
            Role = model.Role,
            Department = AccessRules.DepartmentScope(model.Role) ?? model.Department,
            IsActive = model.IsActive,
            // Admin-created accounts are trusted immediately — approval only gates self-registration.
            IsApproved = true
        };
        user.PasswordHash = _hasher.HashPassword(user, model.Password!);

        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");

        TempData["Success"] = $"User '{user.Username}' created successfully.";
        return RedirectToAction(nameof(Index));
    }

    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> Edit(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();
        if (IsAuditor && user.Role == UserRole.Admin) return Forbid();

        return View(new UserFormViewModel
        {
            Id = user.Id,
            Username = user.Username,
            FullName = user.FullName,
            Role = user.Role,
            Department = user.Department,
            IsActive = user.IsActive,
            IsApproved = user.IsApproved
        });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> Edit(UserFormViewModel model)
    {
        var user = await _db.Users.FindAsync(model.Id);
        if (user is null) return NotFound();
        if (!AccessRules.CanManageRole(CurrentRole, user.Role) || !AccessRules.CanManageRole(CurrentRole, model.Role)) return Forbid();
        if (user.Role is (UserRole.HeadOfProcessing or UserRole.HeadOfCounselors or UserRole.HeadOfMarketing or UserRole.Owner or UserRole.CountryHead) && !await IsPrimaryAdminActorAsync()) return Forbid();
        if (model.Role is (UserRole.HeadOfProcessing or UserRole.HeadOfCounselors or UserRole.HeadOfMarketing or UserRole.Owner or UserRole.CountryHead) && model.Role != user.Role && !await IsPrimaryAdminActorAsync()) return Forbid();
        if (AccessRules.IsPrimaryAdmin(user))
        {
            if (!await IsPrimaryAdminActorAsync() || model.Role != UserRole.Admin ||
                !model.IsActive || !model.IsApproved ||
                !model.Username.Trim().Equals("admin", StringComparison.OrdinalIgnoreCase)) return Forbid();
        }
        else if (user.Role == UserRole.Admin || model.Role == UserRole.Admin) return Forbid();
        if (model.Role == UserRole.SuperAdmin || model.Username.Trim().Equals("admin", StringComparison.OrdinalIgnoreCase))
        {
            if (!AccessRules.IsPrimaryAdmin(user)) return Forbid();
        }

        var normalizedUsername = model.Username.Trim().ToLowerInvariant();
        if (await _db.Users.AnyAsync(u => u.Username.ToLower() == normalizedUsername && u.Id != model.Id))
        {
            ModelState.AddModelError(nameof(model.Username), "This username is already taken.");
        }

        if (!ModelState.IsValid)
        {
            return View(model);
        }

        user.Username = model.Username.Trim();
        user.FullName = model.FullName;
        user.Role = model.Role;
        user.Department = AccessRules.DepartmentScope(model.Role) ?? model.Department;
        user.IsActive = model.IsActive;
        user.IsApproved = model.IsApproved;
        // Saving from the admin panel also clears any lockout, so this doubles as an "unlock" action.
        user.FailedLoginAttempts = 0;
        user.LockedUntil = null;

        if (!string.IsNullOrWhiteSpace(model.Password))
        {
            user.PasswordHash = _hasher.HashPassword(user, model.Password);
        }

        await _db.SaveChangesAsync();
        _activeCache.Invalidate(user.Id);
        await _realtime.NotifyAsync("users");
        TempData["Success"] = $"User '{user.Username}' updated successfully.";
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> Approve(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is not null && (AccessRules.IsPrimaryAdmin(user) || !AccessRules.CanManageRole(CurrentRole, user.Role) ||
            (user.Role is (UserRole.HeadOfMarketing or UserRole.HeadOfProcessing or UserRole.HeadOfCounselors) && !await IsPrimaryAdminActorAsync()))) return Forbid();
        if (user is not null)
        {
            user.IsApproved = true;
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("users");
            TempData["Success"] = $"User '{user.Username}' approved.";
        }
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> ApprovePasswordReset(int id)
    {
        var pending = await _db.PendingPasswordResets.Include(p => p.User).FirstOrDefaultAsync(p => p.Id == id);
        if (pending?.User is not null && IsAuditor && pending.User.Role == UserRole.Admin) return Forbid();
        if (pending?.User is not null)
        {
            var user = pending.User;
            user.PasswordHash = pending.NewPasswordHash;
            user.FailedLoginAttempts = 0;
            user.LockedUntil = null;
            _db.PendingPasswordResets.Remove(pending);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("password-resets");

            // Store-and-forward via FCM — delivers whenever this device is next
            // online, whether or not the employee is checked in right now.
            if (!string.IsNullOrWhiteSpace(user.FcmToken))
            {
                await _fcm.SendNotificationAsync(
                    user.FcmToken,
                    "Password updated",
                    "Your password was updated. You can now log in with your new password.");
            }
            TempData["Success"] = $"Password updated for '{user.Username}'.";
        }
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> RejectPasswordReset(int id)
    {
        var pending = await _db.PendingPasswordResets.Include(p => p.User).FirstOrDefaultAsync(p => p.Id == id);
        if (pending is not null && IsAuditor && pending.User?.Role == UserRole.Admin) return Forbid();
        if (pending is not null)
        {
            _db.PendingPasswordResets.Remove(pending);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("password-resets");
            TempData["Success"] = "Request dismissed.";
        }
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> SetMarketingAdmin(int id, bool enabled)
    {
        if (!await IsPrimaryAdminActorAsync()) return Forbid();
        var target = await _db.Users.FindAsync(id);
        if (target == null) return NotFound();
        if (AccessRules.IsPrimaryAdmin(target) ||
            target.Role is not (UserRole.Employee or UserRole.HeadOfMarketing or UserRole.Admin) ||
            target.Department != EmployeeDepartment.Marketing) return BadRequest("Only a Marketing Head can have admin access granted or revoked here.");
        if (enabled && target.Role != UserRole.Employee) return BadRequest("Already has admin access.");
        if (!enabled && target.Role is not (UserRole.Admin or UserRole.HeadOfMarketing)) return BadRequest("No admin access to revoke.");
        target.Role = enabled ? UserRole.HeadOfMarketing : UserRole.Employee;
        await _db.SaveChangesAsync();
        _activeCache.Invalidate(target.Id);
        await _realtime.NotifyAsync("users");
        TempData["Success"] = enabled ? "Marketing Head granted admin access." : "Marketing Head admin access removed.";
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> ResetDevice(int id)
    {
        var u = await _db.Users.FindAsync(id);
        if (u == null) return NotFound();
        if (!AccessRules.CanManageRole(CurrentRole, u.Role) || AccessRules.IsPrimaryAdmin(u)) return Forbid();
        u.HomeDeviceId = null; u.LastDeviceId = null; u.LastDeviceLoginAt = null; u.FcmToken = null;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");
        TempData["Success"] = $"Device binding reset for '{u.Username}'. They must log in with password on their new phone.";
        return RedirectToAction(nameof(Details), new { id });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(AuthenticationSchemes = "Cookies", Roles = "Admin,Owner,SuperAdmin")]
    public async Task<IActionResult> Delete(int id)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is not null && (AccessRules.IsPrimaryAdmin(user) || !AccessRules.CanManageRole(CurrentRole, user.Role) ||
            (user.Role is (UserRole.HeadOfMarketing or UserRole.HeadOfProcessing or UserRole.HeadOfCounselors) && !await IsPrimaryAdminActorAsync()))) return Forbid();
        if (user is not null)
        {
            if (AccessRules.IsPrimaryAdmin(user)) return Forbid();
            _db.Users.Remove(user);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("users");
            TempData["Success"] = $"User '{user.Username}' deleted.";
        }
        return RedirectToAction(nameof(Index));
    }
}
