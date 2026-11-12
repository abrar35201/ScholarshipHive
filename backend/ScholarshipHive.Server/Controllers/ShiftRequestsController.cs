using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers;
public class ShiftRequestsController:Controller
{
  private readonly AppDbContext _db;private readonly RealtimeNotifier _rt;private readonly FcmPushService _fcm;
  public ShiftRequestsController(AppDbContext db,RealtimeNotifier rt,FcmPushService fcm){_db=db;_rt=rt;_fcm=fcm;}
  [Authorize(Policy="AdminOnly")]
  public async Task<IActionResult> Index()=>View(await _db.ShiftChangeRequests.Include(x=>x.User).OrderBy(x=>x.Status=="Pending"?0:1).ThenByDescending(x=>x.CreatedAt).Take(200).ToListAsync());
  [Authorize(AuthenticationSchemes=CookieAuthenticationDefaults.AuthenticationScheme, Roles="Employee,Receptionist,Auditor,HeadOfMarketing,HeadOfProcessing,HeadOfCounselors,CountryHead,Admin,SuperAdmin,Owner")]
  [HttpGet]
  public async Task<IActionResult> Mine()
  {
    if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return Forbid();
    var user=await _db.Users.AsNoTracking().FirstOrDefaultAsync(x=>x.Id==id&&x.IsActive&&x.IsApproved);
    if(user==null||AccessRules.IsPrimaryAdmin(user))return Forbid();
    ViewBag.ShiftType=user.ShiftType;
    return View(await _db.ShiftChangeRequests.AsNoTracking().Where(x=>x.UserId==id).OrderByDescending(x=>x.CreatedAt).Take(100).ToListAsync());
  }
  [Authorize(AuthenticationSchemes=CookieAuthenticationDefaults.AuthenticationScheme, Roles="Employee,Receptionist,Auditor,HeadOfMarketing,HeadOfProcessing,HeadOfCounselors,CountryHead,Admin,SuperAdmin,Owner")]
  [HttpPost,ValidateAntiForgeryToken]
  public async Task<IActionResult> Submit(ShiftType shiftType,TimeOnly start,TimeOnly end,string reason)
  {
    if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return Forbid();
    var user=await _db.Users.FirstOrDefaultAsync(x=>x.Id==id&&x.IsActive&&x.IsApproved);
    if(user==null||AccessRules.IsPrimaryAdmin(user))return Forbid();
    if(string.IsNullOrWhiteSpace(reason)||reason.Length>1000||start==end){TempData["Error"]="Enter valid shift times and a reason.";return RedirectToAction(nameof(Mine));}
    if(await _db.ShiftChangeRequests.AnyAsync(x=>x.UserId==id&&x.Status=="Pending")){TempData["Error"]="You already have a pending shift request.";return RedirectToAction(nameof(Mine));}
    _db.ShiftChangeRequests.Add(new ShiftChangeRequest{UserId=id,ShiftType=shiftType,Start=start,End=end,Reason=reason.Trim()});
    await _db.SaveChangesAsync();await _rt.NotifyAsync("shift-requests");
    TempData["Success"]="Shift request submitted and is Pending.";return RedirectToAction(nameof(Mine));
  }
  [HttpPost,ValidateAntiForgeryToken]
  [Authorize(Policy="AdminOnly")]
  public async Task<IActionResult> Decide(int id,string decision,string? adminNote)
  {
    if(decision is not ("Approved" or "Rejected"))return BadRequest();
    var req=await _db.ShiftChangeRequests.Include(x=>x.User).FirstOrDefaultAsync(x=>x.Id==id);
    if(req==null)return NotFound();
    if(int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var reviewerId)&&req.UserId==reviewerId)return Forbid();
    var reviewedAt=DateTime.UtcNow;
    await using var transaction=await _db.Database.BeginTransactionAsync();
    var changed=await _db.ShiftChangeRequests.Where(x=>x.Id==id&&x.Status=="Pending")
      .ExecuteUpdateAsync(setters=>setters.SetProperty(x=>x.Status,decision).SetProperty(x=>x.ReviewedAt,(DateTime?)reviewedAt)
        .SetProperty(x=>x.ReviewedByUserId,(int?)reviewerId).SetProperty(x=>x.AdminNote,adminNote==null?null:adminNote.Trim()));
    if(changed==0)return Conflict("Already reviewed.");
    if(decision=="Approved"&&req.User!=null){req.User.ShiftStartTime=req.Start;req.User.ShiftEndTime=req.End;req.User.ShiftType=req.ShiftType;await _db.SaveChangesAsync();}
    await transaction.CommitAsync();req.Status=decision;req.ReviewedAt=reviewedAt;req.AdminNote=adminNote?.Trim();
    await _rt.NotifyAsync("shift-requests");await _rt.NotifyAsync("users");
    if(!string.IsNullOrEmpty(req.User?.FcmToken))await _fcm.SendNotificationAsync(req.User.FcmToken,"Shift request "+decision,req.AdminNote??"Your request was reviewed.");
    TempData["Success"]="Shift request "+decision.ToLowerInvariant();return RedirectToAction("Index");
  }
}
