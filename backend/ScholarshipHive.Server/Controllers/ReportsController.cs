using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnly")]
public class ReportsController : Controller
{
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _realtime;
    private readonly FcmPushService _fcm;

    public ReportsController(AppDbContext db, RealtimeNotifier realtime, FcmPushService fcm)
    {
        _db = db;
        _realtime = realtime;
        _fcm = fcm;
    }

    // Admin/Auditor can pick any date range for any user; omitting both dates
    // defaults to today (Pakistan business day) rather than "all time". A
    // selected report renders full detail (with review actions) alongside the
    // list — one page, no separate Details navigation.
    public async Task<IActionResult> Index(int? userId, DateTime? fromDate, DateTime? toDate, EmployeeDepartment department = EmployeeDepartment.Calling, int? selectedReportId = null)
    {
        var today = DateTimeExtensions.PakistanToday();
        var selectedFrom = fromDate.HasValue ? DateOnly.FromDateTime(fromDate.Value) : (toDate.HasValue ? DateOnly.FromDateTime(toDate.Value) : today);
        var selectedTo = toDate.HasValue ? DateOnly.FromDateTime(toDate.Value) : (fromDate.HasValue ? DateOnly.FromDateTime(fromDate.Value) : today);

        var query = _db.Reports
            .Include(r => r.User)
            .Include(r => r.Attendance)
            .Include(r => r.Files)
            .Where(r => r.Attendance!.Date >= selectedFrom && r.Attendance!.Date <= selectedTo && r.User!.Department == department)
            .AsQueryable();

        if (userId.HasValue)
        {
            query = query.Where(r => r.UserId == userId.Value);
        }

        ViewBag.Users = await _db.Users.Where(u => u.Department == department).OrderBy(u => u.Username).ToListAsync();
        ViewBag.SelectedUserId = userId;
        ViewBag.SelectedFromDate = selectedFrom.ToString("yyyy-MM-dd");
        ViewBag.SelectedToDate = selectedTo.ToString("yyyy-MM-dd");
        ViewBag.SelectedDepartment = department;

        var reports = await query.OrderByDescending(r => r.Attendance!.Date).ThenBy(r => r.User!.Username).ToListAsync();

        var selected = selectedReportId.HasValue
            ? reports.FirstOrDefault(r => r.Id == selectedReportId.Value)
            : reports.FirstOrDefault();
        ViewBag.SelectedReport = selected;

        return View(reports);
    }

    public async Task<IActionResult> Download(int fileId)
    {
        var file = await _db.ReportFiles.FindAsync(fileId);
        if (file is null) return NotFound();

        return File(file.FileData, file.ContentType ?? "application/octet-stream", file.FileName);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SignOff(int id, EmployeeDepartment department, int? userId, DateTime? fromDate, DateTime? toDate)
    {
        var report = await _db.Reports.FindAsync(id);
        if (report is not null)
        {
            report.ReviewStatus = ReportReviewStatus.SignedOff;
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("reports");
        }
        return RedirectToAction(nameof(Index), new { department, userId, fromDate, toDate, selectedReportId = id });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Flag(int id, EmployeeDepartment department, int? userId, DateTime? fromDate, DateTime? toDate)
    {
        var report = await _db.Reports.FindAsync(id);
        if (report is not null)
        {
            report.ReviewStatus = ReportReviewStatus.Flagged;
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("reports");
        }
        return RedirectToAction(nameof(Index), new { department, userId, fromDate, toDate, selectedReportId = id });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> AskForDetail(int id, EmployeeDepartment department, int? userId, DateTime? fromDate, DateTime? toDate)
    {
        var report = await _db.Reports.Include(r => r.User).Include(r => r.Attendance).FirstOrDefaultAsync(r => r.Id == id);
        if (report is not null)
        {
            report.ReviewStatus = ReportReviewStatus.NeedsMoreDetail;
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("reports");

            if (!string.IsNullOrWhiteSpace(report.User?.FcmToken))
            {
                await _fcm.SendNotificationAsync(
                    report.User.FcmToken,
                    "More detail requested",
                    $"An admin asked for more detail on your {report.Attendance?.Date:MMM d} report.");
            }
        }
        return RedirectToAction(nameof(Index), new { department, userId, fromDate, toDate, selectedReportId = id });
    }
}
