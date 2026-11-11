using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers;
[Authorize(Policy="AdminOnly")]
public class ShiftRequestsController:Controller
{
  private readonly AppDbContext _db;private readonly RealtimeNotifier _rt;private readonly FcmPushService _fcm;
  public ShiftRequestsController(AppDbContext db,RealtimeNotifier rt,FcmPushService fcm){_db=db;_rt=rt;_fcm=fcm;}
  public async Task<IActionResult> Index()=>View(await _db.ShiftChangeRequests.Include(x=>x.User).OrderBy(x=>x.Status=="Pending"?0:1).ThenByDescending(x=>x.CreatedAt).Take(200).ToListAsync());
  [HttpPost,ValidateAntiForgeryToken]
  public async Task<IActionResult> Decide(int id,string decision,string? adminNote)
  {
    if(decision is not ("Approved" or "Rejected"))return BadRequest();
    var req=await _db.ShiftChangeRequests.Include(x=>x.User).FirstOrDefaultAsync(x=>x.Id==id);
    if(req==null)return NotFound();if(req.Status!="Pending")return Conflict("Already reviewed.");
    req.Status=decision;req.ReviewedAt=DateTime.UtcNow;req.ReviewedByUserId=int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    req.AdminNote=adminNote?.Trim();
    if(decision=="Approved"&&req.User!=null){req.User.ShiftStartTime=req.Start;req.User.ShiftEndTime=req.End;req.User.ShiftType=req.ShiftType;}
    await _db.SaveChangesAsync();await _rt.NotifyAsync("shift-requests");await _rt.NotifyAsync("users");
    if(!string.IsNullOrEmpty(req.User?.FcmToken))await _fcm.SendNotificationAsync(req.User.FcmToken,"Shift request "+decision,req.AdminNote??"Your request was reviewed.");
    TempData["Success"]="Shift request "+decision.ToLowerInvariant();return RedirectToAction("Index");
  }
}
