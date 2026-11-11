using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers.Api;
[ApiController,Route("api/team-scope")]
[Authorize(AuthenticationSchemes="Bearer,Cookies",Roles="HeadOfMarketing,HeadOfProcessing,HeadOfCounselors")]
public class TeamScopeApiController:ControllerBase
{
    private readonly AppDbContext _db; private readonly IPasswordHasher<User> _hasher; private readonly RealtimeNotifier _rt;
    public TeamScopeApiController(AppDbContext db,IPasswordHasher<User> hasher,RealtimeNotifier rt){_db=db;_hasher=hasher;_rt=rt;}
    private async Task<EmployeeDepartment?> Scope()
    {
        if(!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var id))return null;
        var me=await _db.Users.FindAsync(id);
        return me is { IsActive:true, IsApproved:true } ? AccessRules.DepartmentScope(me.Role):null;
    }
    // Cookie access is for web read-only calls. Mobile changes need an independently
    // validated JWT: simply combining [Authorize] schemes also authorizes cookies.
    private async Task<bool> HasVerifiedBearerAsync()
    {
        var result = await HttpContext.AuthenticateAsync(JwtBearerDefaults.AuthenticationScheme);
        return result.Succeeded && result.Principal?.Identity?.IsAuthenticated == true &&
            result.Principal.FindFirstValue(ClaimTypes.NameIdentifier) == User.FindFirstValue(ClaimTypes.NameIdentifier) &&
            (result.Principal.IsInRole("HeadOfMarketing") || result.Principal.IsInRole("HeadOfProcessing") ||
             result.Principal.IsInRole("HeadOfCounselors"));
    }
    private bool IsBrowserNavigation => Request.Headers.Accept.ToString().Contains("text/html", StringComparison.OrdinalIgnoreCase) &&
        !Request.Headers.Authorization.ToString().StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase);
    private static bool Allowed(EmployeeDepartment scope, EmployeeDepartment actual) => scope == EmployeeDepartment.MarketingAndInterns ? actual is EmployeeDepartment.Marketing or EmployeeDepartment.Interns : actual == scope;
    public sealed class NewTeamEmployee
    {
        [Required,MinLength(3),MaxLength(50)] public string Username {get;set;}="";
        [Required,MaxLength(100)] public string FullName {get;set;}="";
        [Required,MinLength(8)] public string Password {get;set;}="";
        public EmployeeDepartment? Department {get;set;}
    }
    public sealed class UpdateTeamEmployee { [Required,MaxLength(100)] public string FullName {get;set;}=""; public bool IsActive {get;set;}=true; }
    [HttpGet("summary")]
    public async Task<IActionResult> Summary()
    {
        if (IsBrowserNavigation) return Redirect("/TeamScope");
        var dep=await Scope(); if(!dep.HasValue) return Forbid();
        var employees=_db.Users.Where(u=>u.Role==UserRole.Employee && u.IsActive &&
            (dep.Value==EmployeeDepartment.MarketingAndInterns ?
                (u.Department==EmployeeDepartment.Marketing || u.Department==EmployeeDepartment.Interns) : u.Department==dep.Value));
        var ids=employees.Select(u=>u.Id);
        var today=DateTimeExtensions.PakistanToday();
        return Ok(new {
            Department=dep.Value.ToString(), Employees=await employees.CountAsync(),
            ActiveEmployees=await employees.CountAsync(u=>u.IsActive && u.IsApproved),
            CheckedInToday=await _db.Attendances.CountAsync(a=>ids.Contains(a.UserId) && a.Date==today),
            PresentNow=await _db.Attendances.CountAsync(a=>ids.Contains(a.UserId) && a.Date==today && a.CheckOutTime==null),
            ReportsToday=await _db.Attendances.CountAsync(a=>ids.Contains(a.UserId) && a.Date==today && a.ReportSubmitted),
            PendingLeaves=await _db.LeaveRequests.CountAsync(l=>ids.Contains(l.UserId) && l.Status=="Pending"),
            PendingShifts=await _db.ShiftChangeRequests.CountAsync(x=>ids.Contains(x.UserId) && x.Status=="Pending")
        });
    }
    [HttpGet("employees")]
    public async Task<IActionResult> List()
    {
        if (IsBrowserNavigation) return Redirect("/TeamScope");
        var dep=await Scope();if(!dep.HasValue)return Forbid();
        return Ok(await _db.Users.Where(u=>u.Role==UserRole.Employee&&u.IsActive&&(dep.Value == EmployeeDepartment.MarketingAndInterns ? (u.Department==EmployeeDepartment.Marketing || u.Department==EmployeeDepartment.Interns) : u.Department==dep.Value))
            .OrderBy(u=>u.FullName).Select(u=>new{u.Id,u.Username,u.FullName,Department=u.Department.ToString(),u.IsActive,u.IsApproved,u.ShiftStartTime,u.ShiftEndTime}).ToListAsync());
    }
    // A browser opening /api/team-scope/employees/8 used to get HTTP 405, because
    // that URL previously supported only PUT/DELETE. Keep modifications strictly
    // on protected POST/PUT/DELETE routes and offer a safe read-only detail view.
    [HttpGet("employees/{id:int}")]
    public async Task<IActionResult> Employee(int id)
    {
        var dep = await Scope(); if (!dep.HasValue) return Forbid();
        var u = await _db.Users.FirstOrDefaultAsync(x => x.Id == id && x.Role == UserRole.Employee &&
            (dep.Value == EmployeeDepartment.MarketingAndInterns ?
             (x.Department == EmployeeDepartment.Marketing || x.Department == EmployeeDepartment.Interns) :
             x.Department == dep.Value));
        if (u == null) return NotFound();
        if (IsBrowserNavigation) return Redirect($"/TeamScope/Records/{id}");
        return Ok(new { u.Id, u.Username, u.FullName, Department = u.Department.ToString(),
            u.IsActive, u.IsApproved, u.ShiftStartTime, u.ShiftEndTime });
    }
    [HttpGet("employees/{id:int}/records")]
    public async Task<IActionResult> Records(int id)
    {
        if (IsBrowserNavigation) return Redirect($"/TeamScope/Records/{id}");
        var dep=await Scope();if(!dep.HasValue)return Forbid();
        if(!await _db.Users.AnyAsync(u=>u.Id==id&&u.Role==UserRole.Employee&&(dep.Value == EmployeeDepartment.MarketingAndInterns ? (u.Department==EmployeeDepartment.Marketing || u.Department==EmployeeDepartment.Interns) : u.Department==dep.Value)))return NotFound();
        var result=await _db.Attendances.Where(a=>a.UserId==id).OrderByDescending(a=>a.Date).Take(90)
            .Select(a=>new {a.Date,a.CheckInTime,a.CheckOutTime,a.ReportSubmitted,ReportText=a.Report==null?null:a.Report.TextContent}).ToListAsync();
        return Ok(result);
    }
    [HttpPost("employees")]
    public async Task<IActionResult> Add([FromBody] NewTeamEmployee input)
    {
        if (!await HasVerifiedBearerAsync()) return Unauthorized();
        var dep=await Scope();if(!dep.HasValue)return Forbid();
        var username=input.Username.Trim();var fullName=input.FullName.Trim();
        if(username.Length<3||fullName.Length<2||username.Equals("admin",StringComparison.OrdinalIgnoreCase))return BadRequest(new{message="Invalid employee details."});
        if(await _db.Users.AnyAsync(u=>u.Username.ToLower()==username.ToLower()))return Conflict(new{message="Username taken."});
        var chosen = input.Department ?? (dep.Value == EmployeeDepartment.MarketingAndInterns ? EmployeeDepartment.Marketing : dep.Value);
        if (!Allowed(dep.Value, chosen)) return Forbid();
        var u=new User{Username=username,FullName=fullName,Role=UserRole.Employee,Department=chosen,IsActive=true,IsApproved=true};
        u.PasswordHash=_hasher.HashPassword(u,input.Password);_db.Users.Add(u);await _db.SaveChangesAsync();await _rt.NotifyAsync("users");return Ok(new{u.Id,u.Username,u.FullName});
    }
    [HttpPut("employees/{id:int}")]
    public async Task<IActionResult> Update(int id,[FromBody] UpdateTeamEmployee input)
    {
        if (!await HasVerifiedBearerAsync()) return Unauthorized();
        var dep=await Scope();if(!dep.HasValue)return Forbid();
        var u=await _db.Users.FirstOrDefaultAsync(x=>x.Id==id&&x.Role==UserRole.Employee&&(dep.Value == EmployeeDepartment.MarketingAndInterns ? (x.Department==EmployeeDepartment.Marketing || x.Department==EmployeeDepartment.Interns) : x.Department==dep.Value));
        if(u==null)return NotFound();var name=input.FullName.Trim();if(name.Length<2)return BadRequest();
        u.FullName=name;u.IsActive=input.IsActive;await _db.SaveChangesAsync();await _rt.NotifyAsync("users");return Ok(new{u.Id,u.Username,u.FullName,u.IsActive});
    }
    // Remove employee from active department roster without destroying historical
    // attendance, reporting, announcements, or audit records. Only own staff.
    // Do not hard-delete a User: the data model has cascading FKs to records.
    [HttpDelete("employees/{id:int}")]
    public async Task<IActionResult> Remove(int id)
    {
        if (!await HasVerifiedBearerAsync()) return Unauthorized();
        var dep = await Scope(); if (!dep.HasValue) return Forbid();
        var u = await _db.Users.FirstOrDefaultAsync(x => x.Id == id && x.Role == UserRole.Employee &&
            (dep.Value == EmployeeDepartment.MarketingAndInterns ?
              (x.Department == EmployeeDepartment.Marketing || x.Department == EmployeeDepartment.Interns) : x.Department == dep.Value));
        if (u == null) return NotFound();
        u.IsActive = false;
        u.FcmToken = null;
        await _db.SaveChangesAsync();
        await _rt.NotifyAsync("users");
        return Ok(new { message = "Employee removed from active roster. Historical records preserved." });
    }
}
