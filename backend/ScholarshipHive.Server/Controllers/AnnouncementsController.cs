using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers;
[Authorize(Policy = "AnnouncementWeb")]
[Route("Announcements")]
public class AnnouncementsController : Controller
{
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _realtime;
    private readonly FcmPushService _fcm;
    public AnnouncementsController(AppDbContext db, RealtimeNotifier realtime, FcmPushService fcm)
    { _db=db; _realtime=realtime; _fcm=fcm; }
    private int MyId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    [HttpGet("")]
    public async Task<IActionResult> Index()
    {
        var me=await _db.Users.FindAsync(MyId);
        if (me==null) return Forbid();
        ViewBag.CanPublish=AccessRules.CanCreateNotices(me.Role);
        ViewBag.Scope=AccessRules.DepartmentScope(me.Role);
        var q=_db.Announcements.Include(x=>x.Author).Include(x=>x.LastEditedByUser).Where(x=>!x.IsDeleted);
        if (!AccessRules.IsBroadManager(me.Role)) q=q.Where(x=>x.Department==null ||
            (me.Role==UserRole.HeadOfMarketing && (x.Department==EmployeeDepartment.MarketingAndInterns || x.Department==EmployeeDepartment.Marketing || x.Department==EmployeeDepartment.Interns)) ||
            (me.Role==UserRole.HeadOfProcessing && x.Department==EmployeeDepartment.Processing) ||
            (me.Role==UserRole.HeadOfCounselors && x.Department==EmployeeDepartment.Calling) ||
            (me.Role==UserRole.Receptionist && x.Department==EmployeeDepartment.Reception));
        ViewBag.CanDeleteAny = AccessRules.IsOwner(me.Role);
        ViewBag.CurrentId = me.Id;
        return View(await q.OrderByDescending(x=>x.CreatedAt).Take(150).ToListAsync());
    }
    [HttpGet("Feed")]
    public async Task<IActionResult> Feed()
    {
        var me=await _db.Users.FindAsync(MyId);
        if(me==null || !me.IsActive || !me.IsApproved) return Unauthorized();
        var q=_db.Announcements.Include(x=>x.Author).Include(x=>x.LastEditedByUser).Where(x=>!x.IsDeleted);
        if(!AccessRules.IsBroadManager(me.Role)) q=q.Where(x=>x.Department==null ||
            (me.Role==UserRole.HeadOfMarketing && (x.Department==EmployeeDepartment.MarketingAndInterns || x.Department==EmployeeDepartment.Marketing || x.Department==EmployeeDepartment.Interns)) ||
            (me.Role==UserRole.HeadOfProcessing && x.Department==EmployeeDepartment.Processing) ||
            (me.Role==UserRole.HeadOfCounselors && x.Department==EmployeeDepartment.Calling) ||
            (me.Role==UserRole.Receptionist && x.Department==EmployeeDepartment.Reception));
        return Json((await q.OrderByDescending(x=>x.CreatedAt).Take(100).ToListAsync())
            .Select(x=>new{x.Id,x.Title,x.Body,x.UpdatedAt,Author=x.LastEditedByUser?.FullName??x.Author?.FullName??"Management",AuthorRole=AccessRules.DisplayRole(x.LastEditedByUser?.Role??x.Author?.Role??UserRole.Employee),OriginallyBy=x.Author?.FullName??"Management",WasEdited=x.LastEditedByUserId.HasValue}));
    }
    [HttpPost("Save"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Save(int id, string title, string body, EmployeeDepartment? department)
    {
        var me=await _db.Users.FindAsync(MyId);
        if(me==null||!AccessRules.CanCreateNotices(me.Role)) return Forbid();
        if (string.IsNullOrWhiteSpace(title)||string.IsNullOrWhiteSpace(body)||title.Length>160||body.Length>3000) return BadRequest("Invalid announcement.");
        var notice=id==0? new Announcement{AuthorId=me.Id}:await _db.Announcements.FindAsync(id);
        if(notice==null||notice.IsDeleted) return NotFound();
        if(id>0&&!AccessRules.CanDeleteAnnouncement(me, notice)) return Forbid();
        var audience=me.Role == UserRole.HeadOfMarketing ? department : AccessRules.DepartmentScope(me.Role)??department;
        if(!AccessRules.CanTargetAudience(me.Role,audience) ||
           (me.Role != UserRole.HeadOfMarketing && AccessRules.DepartmentScope(me.Role).HasValue && department.HasValue && department != audience)) return Forbid();
        var oldAudience = notice.Department;
        notice.Title=title.Trim(); notice.Body=body.Trim(); notice.Department=audience;
        notice.UpdatedAt=DateTime.UtcNow;
        if(id==0) _db.Announcements.Add(notice);
        else
        {
            notice.LastEditedByUserId = me.Id;
            // In addition to the global entity audit, record a searchable editor
            // event (with only audience metadata, never the confidential message).
            _db.AuditEvents.Add(new AuditEvent { Actor=me.Username, EntityType="Announcement",
                Action="Edited", EntityKey=notice.Id.ToString(),
                Details=$"Audience: {oldAudience?.ToString() ?? "Everyone"} -> {audience?.ToString() ?? "Everyone"}" });
        }
        if (id > 0)
        {
            await using var transaction = await _db.Database.BeginTransactionAsync();
            await _db.SaveChangesAsync();
            await transaction.CommitAsync();
        }
        else await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("announcements");
        if (id==0 || oldAudience != notice.Department)
        {
            var recipients=(await _db.Users.Where(u=>u.IsActive&&u.IsApproved&&u.FcmToken!=null).ToListAsync())
                .Where(u=>AccessRules.ReceivesAnnouncement(u,notice.Department))
                .Select(u=>u.FcmToken!).Distinct().ToList();
            foreach(var token in recipients) await _fcm.SendNotificationAsync(token,"Important announcement: "+notice.Title,notice.Body.Length>180?notice.Body[..180]:notice.Body);
        }
        TempData["Success"]="Announcement saved.";return Redirect("/Announcements");
    }
    [HttpPost("Delete"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(int id)
    {
        var me=await _db.Users.FindAsync(MyId);var notice=await _db.Announcements.FindAsync(id);
        if(me==null||notice==null) return NotFound();
        if(!AccessRules.CanCreateNotices(me.Role)||!AccessRules.CanDeleteAnnouncement(me,notice)) return Forbid();
        notice.IsDeleted=true;await _db.SaveChangesAsync();await _realtime.NotifyAsync("announcements");
        TempData["Success"]="Announcement removed.";return Redirect("/Announcements");
    }
}
