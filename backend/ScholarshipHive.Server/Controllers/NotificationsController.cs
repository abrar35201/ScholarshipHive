using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy="AnnouncementWeb")]
public class NotificationsController : Controller
{
    private readonly AppDbContext _db;
    public NotificationsController(AppDbContext db) => _db=db;
    [HttpGet]
    public async Task<IActionResult> Index()
    {
        // Department heads and reception may read their announcements, but must
        // not see the global approvals inbox for other departments.
        if (User.IsInRole("HeadOfMarketing") || User.IsInRole("HeadOfProcessing") ||
            User.IsInRole("HeadOfCounselors") || User.IsInRole("Receptionist"))
            return RedirectToAction("Index", "Announcements");
        ViewBag.Leaves=await _db.LeaveRequests.Include(x=>x.User).Where(x=>x.Status=="Pending").OrderByDescending(x=>x.AppliedAt).Take(100).ToListAsync();
        ViewBag.Shifts=await _db.ShiftChangeRequests.Include(x=>x.User).Where(x=>x.Status=="Pending").OrderByDescending(x=>x.CreatedAt).Take(100).ToListAsync();
        ViewBag.PendingUsers=await _db.Users.CountAsync(x=>!x.IsApproved);
        ViewBag.PendingRouters=await _db.PendingNetworks.CountAsync();
        return View();
    }
}
