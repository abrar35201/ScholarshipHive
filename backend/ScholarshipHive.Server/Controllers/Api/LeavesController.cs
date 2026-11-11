using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers.Api;

public class LeaveApplyDto
{
    [Required] public string Username { get; set; } = "";
    [Required] public string Password { get; set; } = "";
    [Required] public DateOnly LeaveDate { get; set; }
    [Required, MaxLength(24)] public string LeaveType { get; set; } = "Full-Day Leave";
    [Required, MaxLength(1500)] public string Reason { get; set; } = "";
}
public class LeaveStatusDto
{
    [Required] public string Username { get; set; } = "";
    [Required] public string Password { get; set; } = "";
}
public class LeaveDecisionDto
{
    [Required] public string Decision { get; set; } = "";
    [MaxLength(500)] public string? AdminNote { get; set; }
}
[ApiController]
[Route("api/leaves")]
public class LeavesController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IPasswordHasher<User> _hasher;
    private readonly RealtimeNotifier _realtime;
    private readonly FcmPushService _fcmPush;
    public LeavesController(AppDbContext db, IPasswordHasher<User> hasher, RealtimeNotifier realtime, FcmPushService fcmPush)
    { _db = db; _hasher = hasher; _realtime = realtime; _fcmPush = fcmPush; }

    // Separate from attendance: requires real credentials but never checks Wi-Fi/GPS,
    // creates a session or checks anybody in.
    private async Task<User?> VerifyApplicant(string username, string password)
    {
        var name = username.Trim().ToLowerInvariant();
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == name && u.IsActive && u.IsApproved);
        if (user == null || AccessRules.IsPrimaryAdmin(user)) return null;
        if (user.LockedUntil > DateTime.UtcNow) return null;
        return _hasher.VerifyHashedPassword(user, user.PasswordHash, password) == PasswordVerificationResult.Failed ? null : user;
    }

    [HttpPost("apply")]
    [AllowAnonymous]
    public async Task<IActionResult> Apply([FromBody] LeaveApplyDto input)
    {
        if (string.IsNullOrWhiteSpace(input.Reason) || input.LeaveDate == default ||
            input.LeaveDate < DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-1)) ||
            input.LeaveDate > DateOnly.FromDateTime(DateTime.UtcNow.AddYears(2)))
            return BadRequest(new { message = "Enter a valid future leave date and reason." });
        if (input.LeaveType is not ("Full-Day Leave" or "Half-Day Leave"))
            return BadRequest(new { message = "Invalid leave type." });
        var user = await VerifyApplicant(input.Username, input.Password);
        if (user == null) return Unauthorized(new { message = "Invalid credentials or account not approved." });
        // A second application for the same date supersedes, never deletes, the earlier
        // pending application. The newest request is the only actionable one.
        var prior = await _db.LeaveRequests.Where(l => l.UserId == user.Id &&
            l.LeaveDate == input.LeaveDate && l.Status == "Pending")
            .OrderByDescending(l => l.AppliedAt).ToListAsync();
        var reason = input.Reason.Trim();
        if (prior.Count > 0)
        {
            var previousReason = prior[0].Reason;
            foreach (var old in prior) old.Status = "Superseded";
            reason = $"Updated leave request. Previous reason: {previousReason} | New reason: {reason}";
            if (reason.Length > 1500) reason = reason[..1500];
        }
        var leave = new LeaveRequest { UserId = user.Id, LeaveDate = input.LeaveDate,
            LeaveType = input.LeaveType, Reason = reason };
        _db.LeaveRequests.Add(leave);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("leaves");
        var admins = await _db.Users.Where(u => u.IsActive && u.IsApproved && u.Role == UserRole.Admin && u.FcmToken != null)
            .Select(u => u.FcmToken!).ToListAsync();
        foreach (var token in admins)
            await _fcmPush.SendNotificationAsync(token, "Leave approval requested", $"{user.Username} requested {input.LeaveType} on {input.LeaveDate}");
        return Ok(new { leave.Id, leave.Status, message = "Leave request submitted for admin approval." });
    }

    [HttpPost("status")]
    [AllowAnonymous]
    public async Task<IActionResult> Status([FromBody] LeaveStatusDto input)
    {
        var user = await VerifyApplicant(input.Username, input.Password);
        if (user == null) return Unauthorized(new { message = "Invalid credentials or account not approved." });
        var leaves = await _db.LeaveRequests.Where(l => l.UserId == user.Id)
            .OrderByDescending(l => l.AppliedAt).Take(30)
            .Select(l => new { l.Id, l.LeaveDate, l.LeaveType, l.Reason, l.Status, l.AppliedAt, l.ReviewedAt, l.AdminNote }).ToListAsync();
        return Ok(leaves);
    }

    [HttpGet("admin")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Auditor,SuperAdmin,Owner,CountryHead,HeadOfMarketing,HeadOfProcessing")]
    public async Task<IActionResult> AdminList() => Ok(await _db.LeaveRequests.Include(l => l.User)
        .OrderBy(l => l.Status == "Pending" ? 0 : 1).ThenByDescending(l => l.AppliedAt)
        .Take(200).Select(l => new { l.Id, l.UserId, Username = l.User!.Username,
          FullName = l.User.FullName, l.LeaveDate, l.LeaveType, l.Reason, l.Status, l.AppliedAt, l.AdminNote }).ToListAsync());

    [HttpPost("admin/{id:int}/decision")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Auditor,SuperAdmin,Owner,CountryHead,HeadOfMarketing,HeadOfProcessing")]
    public async Task<IActionResult> Decide(int id, [FromBody] LeaveDecisionDto input)
    {
        if (input.Decision is not ("Approved" or "Rejected")) return BadRequest(new { message = "Choose Approved or Rejected." });
        var leave = await _db.LeaveRequests.FindAsync(id);
        if (leave == null) return NotFound();
        if (int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var reviewerId) && leave.UserId == reviewerId)
            return Forbid();
        if (leave.Status != "Pending") return Conflict(new { message = "Leave already reviewed." });
        leave.Status = input.Decision;
        leave.AdminNote = input.AdminNote?.Trim();
        leave.ReviewedAt = DateTime.UtcNow;
        leave.ReviewedByUserId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("leaves");
        return Ok(new { leave.Id, leave.Status });
    }
}
