using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers.Api;
public sealed class AnnouncementInput
{
    [Required, MaxLength(160)] public string Title { get; set; } = "";
    [Required, MaxLength(3000)] public string Body { get; set; } = "";
    public EmployeeDepartment? Department { get; set; }
}
[ApiController]
[Route("api/announcements")]
public class AnnouncementsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly FcmPushService _fcm;
    private readonly RealtimeNotifier _realtime;
    public AnnouncementsController(AppDbContext db, FcmPushService fcm, RealtimeNotifier realtime)
    { _db = db; _fcm = fcm; _realtime = realtime; }
    private int CurrentId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    private async Task<User?> Me() => await _db.Users.FindAsync(CurrentId);
    private static object AsOutput(Announcement a) => new { a.Id, a.Title, a.Body, a.Department,
        DepartmentName = a.Department?.ToString() ?? "Everyone", a.AuthorId,
        // The recipient sees who most recently published/edited the visible text.
        Author = a.LastEditedByUser?.FullName ?? a.Author?.FullName ?? "Management",
        AuthorRole = AccessRules.DisplayRole(a.LastEditedByUser?.Role ?? a.Author?.Role ?? UserRole.Employee),
        OriginalAuthor = a.Author?.FullName ?? "Management", a.LastEditedByUserId,
        WasEdited = a.LastEditedByUserId.HasValue, a.CreatedAt, a.UpdatedAt };

    [HttpGet]
    [Authorize(AuthenticationSchemes = "Bearer,Cookies")]
    public async Task<IActionResult> Index()
    {
        if (User.Identity?.AuthenticationType == "Cookies" || (Request.Headers.Accept.ToString().Contains("text/html") && User.Identity?.IsAuthenticated == true))
            return Redirect("/Announcements");
        var me = await Me();
        if (me == null || !me.IsActive || !me.IsApproved) return Unauthorized();
        var q = _db.Announcements.Include(x => x.Author).Include(x => x.LastEditedByUser).Where(a => !a.IsDeleted);
        if (!AccessRules.IsBroadManager(me.Role))
            q = q.Where(a => a.Department == null ||
                (me.Role == UserRole.HeadOfMarketing && (a.Department == EmployeeDepartment.MarketingAndInterns || a.Department == EmployeeDepartment.Marketing || a.Department == EmployeeDepartment.Interns)) ||
                (me.Role == UserRole.HeadOfProcessing && a.Department == EmployeeDepartment.Processing) ||
                (me.Role == UserRole.HeadOfCounselors && a.Department == EmployeeDepartment.Calling) ||
                (me.Role == UserRole.Receptionist && a.Department == EmployeeDepartment.Reception) ||
                (me.Role == UserRole.Employee && (a.Department == me.Department ||
                    (a.Department == EmployeeDepartment.MarketingAndInterns &&
                     (me.Department == EmployeeDepartment.Marketing || me.Department == EmployeeDepartment.Interns)))));
        var items = await q.OrderByDescending(a => a.CreatedAt).Take(150).ToListAsync();
        return Ok(items.Select(AsOutput));
    }

    [HttpPost]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> Create([FromBody] AnnouncementInput input)
    {
        var me = await Me();
        if (me == null || !me.IsActive || !me.IsApproved || !AccessRules.CanCreateNotices(me.Role)) return Forbid();
        var scope = AccessRules.DepartmentScope(me.Role);
        var department = me.Role == UserRole.HeadOfMarketing ? input.Department : scope ?? input.Department;
        if (!AccessRules.CanTargetAudience(me.Role, department) ||
            (me.Role != UserRole.HeadOfMarketing && scope.HasValue && input.Department.HasValue && input.Department != scope)) return Forbid();
        if (string.IsNullOrWhiteSpace(input.Title) || string.IsNullOrWhiteSpace(input.Body)) return BadRequest(new { message = "Title and message are required." });
        var announcement = new Announcement { Title = input.Title.Trim(), Body = input.Body.Trim(), AuthorId = me.Id,
            Department = department };
        _db.Announcements.Add(announcement);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("announcements");
        var recipients = (await _db.Users.Where(u => u.IsActive && u.IsApproved && u.FcmToken != null)
            .ToListAsync()).Where(u=>AccessRules.ReceivesAnnouncement(u, department))
            .Select(u=>u.FcmToken!).Distinct().ToList();
        foreach (var token in recipients)
            await _fcm.SendNotificationAsync(token, "Important announcement: " + announcement.Title, announcement.Body.Length > 180 ? announcement.Body[..180] : announcement.Body);
        return Ok(new { announcement.Id });
    }

    [HttpPut("{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> Edit(int id, [FromBody] AnnouncementInput input)
    {
        var me = await Me(); var entry = await _db.Announcements.FindAsync(id);
        if (me == null || entry == null || entry.IsDeleted) return NotFound();
        if (!AccessRules.CanCreateNotices(me.Role) || !AccessRules.CanDeleteAnnouncement(me, entry)) return Forbid();
        if (string.IsNullOrWhiteSpace(input.Title) || string.IsNullOrWhiteSpace(input.Body)) return BadRequest();
        var oldAudience = entry.Department;
        entry.Title = input.Title.Trim(); entry.Body = input.Body.Trim();
        var audience = me.Role == UserRole.HeadOfMarketing ? input.Department : AccessRules.DepartmentScope(me.Role) ?? input.Department;
        if (!AccessRules.CanTargetAudience(me.Role, audience) ||
            (me.Role != UserRole.HeadOfMarketing && AccessRules.DepartmentScope(me.Role).HasValue && input.Department.HasValue && input.Department != audience)) return Forbid();
        entry.Department = audience;
        entry.LastEditedByUserId = me.Id;
        entry.UpdatedAt = DateTime.UtcNow;
        _db.AuditEvents.Add(new AuditEvent { Actor=me.Username, EntityType="Announcement",
            Action="Edited", EntityKey=entry.Id.ToString(),
            Details=$"Audience: {oldAudience?.ToString() ?? "Everyone"} -> {audience?.ToString() ?? "Everyone"}" });
        await using (var transaction = await _db.Database.BeginTransactionAsync())
        {
            await _db.SaveChangesAsync();
            await transaction.CommitAsync();
        }
        await _realtime.NotifyAsync("announcements");
        if (oldAudience != audience)
        {
            var recipients = (await _db.Users.Where(u => u.IsActive && u.IsApproved && u.FcmToken != null)
                .ToListAsync()).Where(u => AccessRules.ReceivesAnnouncement(u, audience))
                .Select(u => u.FcmToken!).Distinct().ToList();
            foreach (var token in recipients)
                await _fcm.SendNotificationAsync(token, "Important announcement: " + entry.Title,
                    entry.Body.Length > 180 ? entry.Body[..180] : entry.Body);
        }
        return Ok(new { entry.Id });
    }

    [HttpDelete("{id:int}")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> Delete(int id)
    {
        var me = await Me(); var entry = await _db.Announcements.FindAsync(id);
        if (me == null || entry == null) return NotFound();
        if (!AccessRules.CanCreateNotices(me.Role) || !AccessRules.CanDeleteAnnouncement(me, entry)) return Forbid();
        entry.IsDeleted = true;
        await _db.SaveChangesAsync(); await _realtime.NotifyAsync("announcements");
        return Ok(new { entry.Id });
    }
}
