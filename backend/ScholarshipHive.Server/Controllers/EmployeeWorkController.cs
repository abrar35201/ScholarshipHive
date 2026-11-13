using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

// Web is a work interface only. Never creates check-ins, check-outs, pings,
// device IDs or attendance durations. Only an existing mobile network check-in
// can create the attendance record to which a report may be attached.
[Authorize(AuthenticationSchemes = CookieAuthenticationDefaults.AuthenticationScheme, Roles = "Employee")]
[Route("EmployeeWork")]
public sealed class EmployeeWorkController : Controller
{
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _rt;
    public EmployeeWorkController(AppDbContext db, RealtimeNotifier rt) { _db = db; _rt = rt; }
    private async Task<User?> CurrentEmployeeAsync()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return null;
        return await _db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == id && u.Role == UserRole.Employee && u.IsActive && u.IsApproved);
    }
    [HttpGet("")]
    public async Task<IActionResult> Index()
    {
        var user = await CurrentEmployeeAsync(); if (user == null) return Forbid();
        var today = DateTimeExtensions.PakistanToday();
        var attendance = await _db.Attendances.AsNoTracking().Include(a => a.Report)
            .FirstOrDefaultAsync(a => a.UserId == user.Id && a.Date == today);
        ViewBag.Attendance = attendance;
        ViewBag.Department = user.Department;
        ViewBag.Today = today;
        var since = new DateOnly(today.Year, today.Month, 1).AddMonths(-1);
        var previous = await _db.Reports.AsNoTracking().Include(r => r.Attendance)
            .Where(r => r.UserId == user.Id && r.Attendance != null && r.Attendance.Date >= since)
            .OrderByDescending(r => r.SubmittedAt).Take(60).ToListAsync();
        return View(previous);
    }
    [HttpPost("Submit"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Submit(int unreadChats, int newLeads, int qualifiedLeads, int followUp,
        int calls, int potential, int walkIns, int conversion, string? textContent)
    {
        var user = await CurrentEmployeeAsync(); if (user == null) return Forbid();
        var values = new[] { unreadChats, newLeads, qualifiedLeads, followUp, calls, potential, walkIns, conversion };
        if (values.Any(v => v < 0 || v > 999) || textContent?.Length > 15000)
        {
            TempData["Error"] = "Invalid report values (0–999) or text too long.";
            return RedirectToAction(nameof(Index));
        }
        var today = DateTimeExtensions.PakistanToday();
        var attendance = await _db.Attendances.Include(a => a.Report)
            .FirstOrDefaultAsync(a => a.UserId == user.Id && a.Date == today);
        if (attendance == null)
        {
            TempData["Error"] = "No phone attendance today. Connect your phone to approved office Wi-Fi and check in first. Web login does not count work time.";
            return RedirectToAction(nameof(Index));
        }
        var report = attendance.Report;
        if (report == null)
        {
            report = new Report { UserId = user.Id, AttendanceId = attendance.Id, SubmittedAt = DateTime.UtcNow };
            _db.Reports.Add(report);
            attendance.Report = report;
        }
        else report.LastEditedAt = DateTime.UtcNow;
        report.UnreadChats = unreadChats;
        report.NewLeads = newLeads;
        report.QualifiedLeads = qualifiedLeads;
        report.FollowUp = followUp;
        report.Calls = calls;
        report.Potential = potential;
        report.WalkIns = walkIns;
        report.Conversion = conversion;
        report.TextContent = textContent;
        attendance.ReportSubmitted = true;
        await _db.SaveChangesAsync();
        await _rt.NotifyAsync("reports");
        TempData["Success"] = "Today's report saved. Work hours continue to be calculated only from the phone attendance flow.";
        return RedirectToAction(nameof(Index));
    }
}
