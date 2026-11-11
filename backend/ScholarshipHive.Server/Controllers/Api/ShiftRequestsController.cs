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
public sealed class ShiftChangeInput
{
    [Required] public string Username { get; set; } = "";
    [Required] public string Password { get; set; } = "";
    public ShiftType ShiftType { get; set; }
    public TimeOnly Start { get; set; }
    public TimeOnly End { get; set; }
    [Required, MaxLength(1000)] public string Reason { get; set; } = "";
}
public sealed class ShiftDecisionInput { [Required] public string Decision {get;set;}=""; public string? AdminNote{get;set;} }
[ApiController]
[Route("api/shift-requests")]
public class ShiftRequestsController : ControllerBase
{
    private readonly AppDbContext _db;private readonly IPasswordHasher<User> _hasher;
    private readonly RealtimeNotifier _realtime;private readonly FcmPushService _fcm;
    public ShiftRequestsController(AppDbContext db,IPasswordHasher<User> hasher,RealtimeNotifier realtime,FcmPushService fcm)
    { _db=db;_hasher=hasher;_realtime=realtime;_fcm=fcm; }
    private async Task<User?> Verify(string username,string password)
    {
        var n=username.Trim().ToLowerInvariant();
        var u=await _db.Users.FirstOrDefaultAsync(x=>x.Username.ToLower()==n&&x.IsActive&&x.IsApproved&&(x.Role != UserRole.Admin || x.Username.ToLower() != "admin"));
        return u==null||u.LockedUntil>DateTime.UtcNow||_hasher.VerifyHashedPassword(u,u.PasswordHash,password)==PasswordVerificationResult.Failed?null:u;
    }
    [HttpPost("apply"),AllowAnonymous]
    public async Task<IActionResult> Apply([FromBody] ShiftChangeInput input)
    {
        if(string.IsNullOrWhiteSpace(input.Reason)||input.Reason.Length>1000||input.Start==input.End) return BadRequest(new{message="Valid times and a reason are required."});
        var user=await Verify(input.Username,input.Password);
        if(user==null)return Unauthorized(new{message="Invalid credentials or account not approved."});
        if(await _db.ShiftChangeRequests.AnyAsync(x=>x.UserId==user.Id&&x.Status=="Pending"))return Conflict(new{message="You already have a pending shift request."});
        var entry=new ShiftChangeRequest{UserId=user.Id,ShiftType=input.ShiftType,Start=input.Start,End=input.End,Reason=input.Reason.Trim()};
        _db.ShiftChangeRequests.Add(entry);await _db.SaveChangesAsync();await _realtime.NotifyAsync("shift-requests");
        var tokens=await _db.Users.Where(u=>u.IsActive&&u.IsApproved&&u.FcmToken!=null&&(u.Role==UserRole.Admin||u.Role==UserRole.SuperAdmin||u.Role==UserRole.Owner||u.Role==UserRole.CountryHead||u.Role==UserRole.HeadOfMarketing||u.Role==UserRole.HeadOfProcessing)).Select(u=>u.FcmToken!).ToListAsync();
        foreach(var t in tokens)await _fcm.SendNotificationAsync(t,"Shift approval requested",$"{user.Username} requested {input.Start:HH:mm}–{input.End:HH:mm}.");
        return Ok(new{entry.Id,entry.Status});
    }
    [HttpPost("status"),AllowAnonymous]
    public async Task<IActionResult> Status([FromBody] ShiftChangeInput input)
    {
        var u=await Verify(input.Username,input.Password);if(u==null)return Unauthorized();
        return Ok(await _db.ShiftChangeRequests.Where(x=>x.UserId==u.Id).OrderByDescending(x=>x.CreatedAt).Take(30).ToListAsync());
    }
    [HttpGet("admin")]
    [Authorize(AuthenticationSchemes=JwtBearerDefaults.AuthenticationScheme,Roles="SuperAdmin,Admin,Owner,CountryHead")]
    public async Task<IActionResult> AdminList()=>Ok(await _db.ShiftChangeRequests.Include(x=>x.User).OrderBy(x=>x.Status=="Pending"?0:1).ThenByDescending(x=>x.CreatedAt).Take(150)
        .Select(x=>new{x.Id,x.UserId,Username=x.User!.Username,x.ShiftType,x.Start,x.End,x.Reason,x.Status,x.CreatedAt,x.AdminNote}).ToListAsync());
    [HttpPost("admin/{id:int}/decision")]
    [Authorize(AuthenticationSchemes=JwtBearerDefaults.AuthenticationScheme,Roles="SuperAdmin,Admin,Owner")]
    public async Task<IActionResult> Decision(int id,[FromBody] ShiftDecisionInput input)
    {
        if(input.Decision is not ("Approved" or "Rejected"))return BadRequest();
        var request=await _db.ShiftChangeRequests.Include(x=>x.User).FirstOrDefaultAsync(x=>x.Id==id);
        if(request==null)return NotFound();
        if(int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var reviewerId) && request.UserId==reviewerId) return Forbid();
        if(request.Status!="Pending")return Conflict(new{message="Already reviewed."});
        request.Status=input.Decision;request.ReviewedAt=DateTime.UtcNow;
        request.ReviewedByUserId=int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        request.AdminNote=input.AdminNote?.Trim();
        if(input.Decision=="Approved"&&request.User!=null){request.User.ShiftStartTime=request.Start;request.User.ShiftEndTime=request.End;request.User.ShiftType=request.ShiftType;}
        await _db.SaveChangesAsync();await _realtime.NotifyAsync("users");await _realtime.NotifyAsync("shift-requests");
        if(!string.IsNullOrEmpty(request.User?.FcmToken))await _fcm.SendNotificationAsync(request.User.FcmToken,"Shift request "+request.Status,request.AdminNote??"Your shift request was reviewed.");
        return Ok(new{request.Id,request.Status});
    }
}
