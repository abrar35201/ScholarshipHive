using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using System.Globalization;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers;
[Authorize(Policy="TeamHeadWeb")]
public class TeamScopeController : Controller
{
    private readonly AppDbContext _db;
    private readonly IPasswordHasher<User> _hasher;
    private readonly RealtimeNotifier _realtime;
    private readonly AttendanceDurationService _duration;
    public TeamScopeController(AppDbContext db, IPasswordHasher<User> hasher, RealtimeNotifier realtime, AttendanceDurationService duration) { _db=db; _hasher=hasher; _realtime=realtime; _duration=duration; }
    private async Task<EmployeeDepartment?> MyDepartment()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return null;
        var me=await _db.Users.FindAsync(id);
        return me is { IsActive:true, IsApproved:true } ? AccessRules.DepartmentScope(me.Role) : null;
    }
    [HttpGet("/TeamScope")]
    public async Task<IActionResult> Index(string? q)
    {
        var department=await MyDepartment(); if (!department.HasValue) return Forbid();
        ViewBag.Department=department.Value.ToString();
        var team = _db.Users.Where(u=>u.Role==UserRole.Employee && u.IsActive &&
            (department.Value==EmployeeDepartment.MarketingAndInterns ?
             (u.Department==EmployeeDepartment.Marketing || u.Department==EmployeeDepartment.Interns) : u.Department==department.Value));
        // Search is limited to the signed-in head's own department. Never widen scope.
        q = q?.Trim();
        if (!string.IsNullOrEmpty(q))
        {
            if (q.Length > 100) q = q[..100];
            team = team.Where(u => u.FullName.Contains(q) || u.Username.Contains(q));
        }
        ViewBag.SearchQuery = q;
        // Dashboard counters represent the whole team, not just search results.
        var ids = _db.Users.Where(u => u.Role == UserRole.Employee && u.IsActive &&
            (department.Value == EmployeeDepartment.MarketingAndInterns ?
                (u.Department == EmployeeDepartment.Marketing || u.Department == EmployeeDepartment.Interns) :
                u.Department == department.Value)).Select(u => u.Id);
        ViewBag.TeamTotal = await ids.CountAsync();
        var today = DateTimeExtensions.PakistanToday();
        ViewBag.CountToday = await _db.Attendances.CountAsync(a=>ids.Contains(a.UserId) && a.Date==today);
        ViewBag.PresentNow = await _db.Attendances.CountAsync(a=>ids.Contains(a.UserId) && a.Date==today && a.CheckOutTime==null);
        ViewBag.ReportsToday = await _db.Attendances.CountAsync(a=>ids.Contains(a.UserId) && a.Date==today && a.ReportSubmitted);
        ViewBag.PendingLeaves = await _db.LeaveRequests.CountAsync(l=>ids.Contains(l.UserId) && l.Status=="Pending");
        ViewBag.PendingShifts = await _db.ShiftChangeRequests.CountAsync(x=>ids.Contains(x.UserId) && x.Status=="Pending");
        return View(await team.OrderBy(u=>u.FullName).ToListAsync());
    }
    [HttpGet("/TeamScope/Hours")]
    public async Task<IActionResult> Hours(string? month)
    {
        var department=await MyDepartment();if(!department.HasValue)return Forbid();
        var today=DateTimeExtensions.PakistanToday();
        var selectedMonth=DateOnly.TryParseExact(month,"yyyy-MM",CultureInfo.InvariantCulture,DateTimeStyles.None,out var parsed)
            ? new DateOnly(parsed.Year,parsed.Month,1) : new DateOnly(today.Year,today.Month,1);
        var currentMonth=new DateOnly(today.Year,today.Month,1);
        if(selectedMonth>currentMonth||selectedMonth.Year==1&&selectedMonth.Month==1)selectedMonth=currentMonth;
        var employees=await _db.Users.Where(u=>u.Role==UserRole.Employee&&u.IsActive&&
            (department.Value==EmployeeDepartment.MarketingAndInterns ?
                (u.Department==EmployeeDepartment.Marketing||u.Department==EmployeeDepartment.Interns) : u.Department==department.Value))
            .OrderBy(u=>u.FullName).ToListAsync();
        var totals=await _duration.ComputeMonthManyAsync(employees.Select(u=>u.Id).ToList(),selectedMonth.Year,selectedMonth.Month,DateTime.UtcNow);
        var rows=employees.Select(u=>new DepartmentMonthlyEmployeeHoursDto
        {
            UserId=u.Id,Name=u.FullName,Department=u.Department.ToString(),
            TotalMinutes=totals[u.Id].TotalMinutes,DaysWorked=totals[u.Id].DaysWorked
        }).OrderByDescending(x=>x.TotalMinutes).ThenBy(x=>x.Name).ToList();
        var model=new DepartmentMonthlyHoursDto
        {
            Year=selectedMonth.Year,Month=selectedMonth.Month,Department=department.Value.ToString(),
            TotalMinutes=rows.Sum(x=>x.TotalMinutes),TotalEmployeeDays=rows.Sum(x=>x.DaysWorked),Employees=rows
        };
        ViewBag.PreviousMonth=selectedMonth.AddMonths(-1).ToString("yyyy-MM",CultureInfo.InvariantCulture);
        ViewBag.NextMonth=selectedMonth.AddMonths(1).ToString("yyyy-MM",CultureInfo.InvariantCulture);
        ViewBag.CurrentMonth=currentMonth.ToString("yyyy-MM",CultureInfo.InvariantCulture);
        return View(model);
    }
    [HttpGet("/TeamScope/Records/{id:int}")]
    public async Task<IActionResult> Records(int id)
    {
        var department=await MyDepartment();if(!department.HasValue)return Forbid();
        var employee=await _db.Users.FirstOrDefaultAsync(u=>u.Id==id&&u.Role==UserRole.Employee&&(department.Value == EmployeeDepartment.MarketingAndInterns ? (u.Department==EmployeeDepartment.Marketing || u.Department==EmployeeDepartment.Interns) : u.Department==department.Value));
        if(employee==null)return NotFound();
        ViewBag.Employee=employee;
        return View(await _db.Attendances.Include(a=>a.Report).Where(a=>a.UserId==id).OrderByDescending(a=>a.Date).Take(90).ToListAsync());
    }
    [HttpPost("/TeamScope/Add"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Add(string username,string fullName,string password, EmployeeDepartment? selectedDepartment)
    {
        var department=await MyDepartment(); if(!department.HasValue)return Forbid();
        username=(username??"").Trim(); fullName=(fullName??"").Trim();
        if(username.Length<3||username.Length>50||fullName.Length<2||fullName.Length>100||string.IsNullOrWhiteSpace(password)||password.Length<8)
        {TempData["Error"]="Enter a valid username, name and a password of at least 8 characters.";return Redirect("/TeamScope");}
        if(username.Equals("admin",StringComparison.OrdinalIgnoreCase)||await _db.Users.AnyAsync(u=>u.Username.ToLower()==username.ToLower()))
        {TempData["Error"]="Username already taken.";return Redirect("/TeamScope");}
        var chosen = selectedDepartment ?? (department.Value == EmployeeDepartment.MarketingAndInterns ? EmployeeDepartment.Marketing : department.Value);
        if (department.Value == EmployeeDepartment.MarketingAndInterns ?
            chosen is not (EmployeeDepartment.Marketing or EmployeeDepartment.Interns) : chosen != department.Value)
            return Forbid();
        var user=new User{Username=username,FullName=fullName,Role=UserRole.Employee,Department=chosen,IsApproved=true,IsActive=true};
        user.PasswordHash=_hasher.HashPassword(user,password);
        _db.Users.Add(user);
        await _db.SaveChangesAsync();await _realtime.NotifyAsync("users");
        TempData["Success"]="Department employee added.";return Redirect("/TeamScope");
    }
    [HttpPost("/TeamScope/Update"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Update(int id,string fullName,bool isActive)
    {
        var department=await MyDepartment();if(!department.HasValue)return Forbid();
        var employee=await _db.Users.FirstOrDefaultAsync(u=>u.Id==id&&u.Role==UserRole.Employee&&(department.Value == EmployeeDepartment.MarketingAndInterns ? (u.Department==EmployeeDepartment.Marketing || u.Department==EmployeeDepartment.Interns) : u.Department==department.Value));
        if(employee==null)return NotFound();
        fullName=(fullName??"").Trim();if(fullName.Length<2||fullName.Length>100)return BadRequest("Invalid name.");
        employee.FullName=fullName;employee.IsActive=isActive;
        await _db.SaveChangesAsync();await _realtime.NotifyAsync("users");
        TempData["Success"]="Employee updated.";return Redirect("/TeamScope");
    }
    [HttpPost("/TeamScope/Remove/{id:int}"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Remove(int id)
    {
        var department = await MyDepartment(); if (!department.HasValue) return Forbid();
        var employee = await _db.Users.FirstOrDefaultAsync(u => u.Id == id && u.Role == UserRole.Employee &&
            (department.Value == EmployeeDepartment.MarketingAndInterns ?
             (u.Department == EmployeeDepartment.Marketing || u.Department == EmployeeDepartment.Interns) :
             u.Department == department.Value));
        if (employee is null) return NotFound();
        employee.IsActive = false; employee.FcmToken = null;
        await _db.SaveChangesAsync(); await _realtime.NotifyAsync("users");
        TempData["Success"] = "Employee removed from the active roster; history and reports preserved.";
        return Redirect("/TeamScope");
    }
}
