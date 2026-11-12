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
    public ShiftType ShiftType { get; set; }
    public TimeOnly Start { get; set; }
    public TimeOnly End { get; set; }
    [Required, MaxLength(1000)] public string Reason { get; set; } = "";
}
public sealed class ShiftChangeCredentialInput
{
    [Required] public string Username { get; set; } = "";
    [Required] public string Password { get; set; } = "";
    public ShiftType ShiftType { get; set; }
    public TimeOnly Start { get; set; }
    public TimeOnly End { get; set; }
    [Required, MaxLength(1000)] public string Reason { get; set; } = "";
}
public sealed class ShiftRequestCredentialInput
{
    [Required] public string Username { get; set; } = "";
    [Required] public string Password { get; set; } = "";
}
public sealed class ShiftDecisionInput { [Required] public string Decision {get;set;}=""; public string? AdminNote{get;set;} }
[ApiController]
[Route("api/shift-requests")]
public class ShiftRequestsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IPasswordHasher<User> _hasher;
    private readonly RealtimeNotifier _realtime;private readonly FcmPushService _fcm;
    public ShiftRequestsController(AppDbContext db,IPasswordHasher<User> hasher,RealtimeNotifier realtime,FcmPushService fcm)
    { _db=db;_hasher=hasher;_realtime=realtime;_fcm=fcm; }
    // This off-network path authenticates each operation with the account password.
    // It does not create a login session, device binding, or attendance record.
    private async Task<User?> VerifyShiftCredentials(string username,string password)
    {
        var normalized=username.Trim().ToLowerInvariant();
        var user=await _db.Users.FirstOrDefaultAsync(x=>x.Username.ToLower()==normalized&&x.IsActive&&x.IsApproved);
        if(user==null)return null;
        if(user.LockedUntil>DateTime.UtcNow)return null;
        if(_hasher.VerifyHashedPassword(user,user.PasswordHash,password)==PasswordVerificationResult.Failed)
        {
            user.FailedLoginAttempts++;
            if(user.FailedLoginAttempts>=AuthPolicy.MaxFailedAttempts){user.LockedUntil=DateTime.UtcNow.Add(AuthPolicy.LockoutDuration);user.FailedLoginAttempts=0;}
            await _db.SaveChangesAsync();
            return null;
        }
        if(AccessRules.IsPrimaryAdmin(user))return null;
        if(user.FailedLoginAttempts!=0||user.LockedUntil.HasValue){user.FailedLoginAttempts=0;user.LockedUntil=null;await _db.SaveChangesAsync();}
        return user;
    }
    private async Task<User?> CurrentRequester()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return null;
        var user = await _db.Users.FirstOrDefaultAsync(x => x.Id == id && x.IsActive && x.IsApproved);
        return user != null && !AccessRules.IsPrimaryAdmin(user) ? user : null;
    }
    [HttpPost("apply"),Authorize(AuthenticationSchemes=JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> Apply([FromBody] ShiftChangeInput input)
    {
        if(string.IsNullOrWhiteSpace(input.Reason)||input.Reason.Length>1000||input.Start==input.End) return BadRequest(new{message="Valid times and a reason are required."});
        var user=await CurrentRequester();
        if(user==null)return Forbid();
        if(await _db.ShiftChangeRequests.AnyAsync(x=>x.UserId==user.Id&&x.Status=="Pending"))return Conflict(new{message="You already have a pending shift request."});
        var entry=new ShiftChangeRequest{UserId=user.Id,ShiftType=input.ShiftType,Start=input.Start,End=input.End,Reason=input.Reason.Trim()};
        _db.ShiftChangeRequests.Add(entry);await _db.SaveChangesAsync();await _realtime.NotifyAsync("shift-requests");
        var tokens=await _db.Users.Where(u=>u.IsActive&&u.IsApproved&&u.FcmToken!=null&&(u.Role==UserRole.Admin||u.Role==UserRole.SuperAdmin||u.Role==UserRole.Owner||u.Role==UserRole.CountryHead||u.Role==UserRole.HeadOfMarketing||u.Role==UserRole.HeadOfProcessing)).Select(u=>u.FcmToken!).ToListAsync();
        foreach(var t in tokens)await _fcm.SendNotificationAsync(t,"Shift approval requested",$"{user.Username} requested {input.Start:HH:mm}–{input.End:HH:mm}.");
        return Ok(new{entry.Id,entry.Status});
    }
    [HttpPost("remote/apply"),AllowAnonymous]
    public async Task<IActionResult> ApplyRemotely([FromBody] ShiftChangeCredentialInput input)
    {
        if(string.IsNullOrWhiteSpace(input.Reason)||input.Reason.Length>1000||input.Start==input.End||!Enum.IsDefined(input.ShiftType))
            return BadRequest(new{message="Valid times, shift type, and a reason are required."});
        var user=await VerifyShiftCredentials(input.Username,input.Password);
        if(user==null)return Unauthorized(new{message="Invalid credentials or account not approved."});
        if(await _db.ShiftChangeRequests.AnyAsync(x=>x.UserId==user.Id&&x.Status=="Pending"))return Conflict(new{message="You already have a pending shift request."});
        var entry=new ShiftChangeRequest{UserId=user.Id,ShiftType=input.ShiftType,Start=input.Start,End=input.End,Reason=input.Reason.Trim()};
        _db.ShiftChangeRequests.Add(entry);await _db.SaveChangesAsync();await _realtime.NotifyAsync("shift-requests");
        var tokens=await _db.Users.Where(u=>u.IsActive&&u.IsApproved&&u.FcmToken!=null&&(u.Role==UserRole.Admin||u.Role==UserRole.SuperAdmin||u.Role==UserRole.Owner||u.Role==UserRole.CountryHead||u.Role==UserRole.HeadOfMarketing||u.Role==UserRole.HeadOfProcessing)).Select(u=>u.FcmToken!).ToListAsync();
        foreach(var token in tokens)await _fcm.SendNotificationAsync(token,"Shift approval requested",$"{user.Username} requested {input.Start:HH:mm}–{input.End:HH:mm}.");
        return Ok(new{entry.Id,entry.Status});
    }
    [HttpPost("remote/mine"),AllowAnonymous]
    public async Task<IActionResult> RemoteMine([FromBody] ShiftRequestCredentialInput input)
    {
        var user=await VerifyShiftCredentials(input.Username,input.Password);
        if(user==null)return Unauthorized(new{message="Invalid credentials or account not approved."});
        return Ok(await _db.ShiftChangeRequests.AsNoTracking().Where(x=>x.UserId==user.Id).OrderByDescending(x=>x.CreatedAt).Take(100)
            .Select(x=>new{x.Id,x.ShiftType,x.Start,x.End,x.Reason,x.Status,x.CreatedAt,x.ReviewedAt,x.AdminNote}).ToListAsync());
    }
    [HttpGet("mine"),Authorize(AuthenticationSchemes=JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> Mine()
    {
        var user=await CurrentRequester();if(user==null)return Forbid();
        return Ok(await _db.ShiftChangeRequests.AsNoTracking().Where(x=>x.UserId==user.Id).OrderByDescending(x=>x.CreatedAt).Take(100)
            .Select(x=>new{x.Id,x.ShiftType,x.Start,x.End,x.Reason,x.Status,x.CreatedAt,x.ReviewedAt,x.AdminNote}).ToListAsync());
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
        var reviewedAt=DateTime.UtcNow;
        await using var transaction=await _db.Database.BeginTransactionAsync();
        var changed=await _db.ShiftChangeRequests.Where(x=>x.Id==id&&x.Status=="Pending")
            .ExecuteUpdateAsync(setters=>setters.SetProperty(x=>x.Status,input.Decision)
                .SetProperty(x=>x.ReviewedAt,(DateTime?)reviewedAt)
                .SetProperty(x=>x.ReviewedByUserId,(int?)reviewerId)
                .SetProperty(x=>x.AdminNote,input.AdminNote==null?null:input.AdminNote.Trim()));
        if(changed==0)return Conflict(new{message="Already reviewed."});
        if(input.Decision=="Approved"&&request.User!=null){request.User.ShiftStartTime=request.Start;request.User.ShiftEndTime=request.End;request.User.ShiftType=request.ShiftType;await _db.SaveChangesAsync();}
        await transaction.CommitAsync();
        request.Status=input.Decision;request.ReviewedAt=reviewedAt;request.ReviewedByUserId=reviewerId;request.AdminNote=input.AdminNote?.Trim();
        await _realtime.NotifyAsync("users");await _realtime.NotifyAsync("shift-requests");
        if(!string.IsNullOrEmpty(request.User?.FcmToken))await _fcm.SendNotificationAsync(request.User.FcmToken,"Shift request "+request.Status,request.AdminNote??"Your shift request was reviewed.");
        return Ok(new{request.Id,request.Status});
    }
}
