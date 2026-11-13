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
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers.Api;
[ApiController,Route("api/team-scope")]
[Authorize(AuthenticationSchemes="Bearer,Cookies",Roles="HeadOfMarketing,HeadOfProcessing,HeadOfCounselors")]
public class TeamScopeApiController:ControllerBase
{
    private readonly AppDbContext _db; private readonly IPasswordHasher<User> _hasher; private readonly RealtimeNotifier _rt; private readonly AttendanceDurationService _duration;
    public TeamScopeApiController(AppDbContext db,IPasswordHasher<User> hasher,RealtimeNotifier rt,AttendanceDurationService duration){_db=db;_hasher=hasher;_rt=rt;_duration=duration;}
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
    [HttpGet("monthly-hours")]
    public async Task<ActionResult<DepartmentMonthlyHoursDto>> MonthlyHours([FromQuery]int? year,[FromQuery]int? month)
    {
        if (IsBrowserNavigation) return Redirect("/TeamScope/Hours");
        var department=await Scope();if(!department.HasValue)return Forbid();
        var today=DateTimeExtensions.PakistanToday();
        var selectedYear=year.GetValueOrDefault(today.Year);
        var selectedMonth=month.GetValueOrDefault(today.Month);
        if(selectedYear<2||selectedYear>DateTime.MaxValue.Year||selectedMonth is <1 or >12)return BadRequest(new{message="Choose a valid month and year."});
        var currentMonth=new DateOnly(today.Year,today.Month,1);
        var selectedDate=new DateOnly(selectedYear,selectedMonth,1);
        if(selectedDate>currentMonth)selectedDate=currentMonth;
        var employees=await _db.Users.Where(u=>u.Role==UserRole.Employee&&u.IsActive&&
            (department.Value==EmployeeDepartment.MarketingAndInterns ?
                (u.Department==EmployeeDepartment.Marketing||u.Department==EmployeeDepartment.Interns) : u.Department==department.Value))
            .OrderBy(u=>u.FullName).ToListAsync();
        var totals=await _duration.ComputeMonthManyAsync(employees.Select(u=>u.Id).ToList(),selectedDate.Year,selectedDate.Month,DateTime.UtcNow);
        var rows=employees.Select(u=>new DepartmentMonthlyEmployeeHoursDto
        {
            UserId=u.Id,Name=u.FullName,Department=u.Department.ToString(),
            TotalMinutes=totals[u.Id].TotalMinutes,DaysWorked=totals[u.Id].DaysWorked
        }).OrderByDescending(x=>x.TotalMinutes).ThenBy(x=>x.Name).ToList();
        return Ok(new DepartmentMonthlyHoursDto
        {
            Year=selectedDate.Year,Month=selectedDate.Month,Department=department.Value.ToString(),
            TotalMinutes=rows.Sum(x=>x.TotalMinutes),TotalEmployeeDays=rows.Sum(x=>x.DaysWorked),Employees=rows
        });
    }
    [HttpGet("employees/{id:int}/monthly-hours")]
    public async Task<IActionResult> EmployeeMonthHours(int id, [FromQuery]int? year, [FromQuery]int? month)
    {
        var dep = await Scope(); if (!dep.HasValue) return Forbid();
        var employee = await _db.Users.FirstOrDefaultAsync(u => u.Id == id &&
            u.Role == UserRole.Employee && u.IsActive &&
            (dep.Value == EmployeeDepartment.MarketingAndInterns ?
                (u.Department == EmployeeDepartment.Marketing || u.Department == EmployeeDepartment.Interns) :
                u.Department == dep.Value));
        if (employee == null) return NotFound();
        var today = DateTimeExtensions.PakistanToday();
        var y = year.GetValueOrDefault(today.Year);
        var m = month.GetValueOrDefault(today.Month);
        if (y < 2 || y > 9999 || m < 1 || m > 12) return BadRequest(new { message = "Invalid month." });
        var selected = new DateOnly(y, m, 1);
        var current = new DateOnly(today.Year, today.Month, 1);
        if (selected > current) selected = current;
        return Ok(await _duration.ComputeEmployeeMonthAsync(employee, selected.Year, selected.Month, DateTime.UtcNow));
    }
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
    // Department heads may reset only the device binding of their own employees.
    // Browser cookies never authorize this sensitive mobile action.
    [HttpPost("employees/{id:int}/reset-device")]
    public async Task<IActionResult> ResetEmployeeDevice(int id)
    {
        if (!await HasVerifiedBearerAsync()) return Unauthorized();
        var dep = await Scope(); if (!dep.HasValue) return Forbid();
        var employee = await _db.Users.FirstOrDefaultAsync(u => u.Id == id && u.Role == UserRole.Employee &&
            (dep.Value == EmployeeDepartment.MarketingAndInterns ?
                (u.Department == EmployeeDepartment.Marketing || u.Department == EmployeeDepartment.Interns) : u.Department == dep.Value));
        if (employee == null) return NotFound();
        employee.HomeDeviceId = null;
        employee.LastDeviceId = null;
        employee.LastDeviceLoginAt = null;
        employee.FcmToken = null;
        await _db.SaveChangesAsync();
        await _rt.NotifyAsync("users");
        return Ok(new { message = "Device reset. Employee must log in again on their phone using password and approved office Wi-Fi." });
    }

}
