using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers.Api;

[ApiController]
[Route("api/reports")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
public class ReportsController : ControllerBase
{
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;
    private const long MaxTotalRequestBytes = 60 * 1024 * 1024;

    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _realtime;

    public ReportsController(AppDbContext db, RealtimeNotifier realtime)
    {
        _db = db;
        _realtime = realtime;
    }

    /// Creates today's report the first time, or updates it on later calls the same
    /// day — a report is only ever editable on the day it's for. Newly attached files
    /// are appended to whatever was already uploaded today, never replaced.
    [HttpPost]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(MaxTotalRequestBytes)]
    public async Task<ActionResult<ReportResponse>> Submit(
        [FromForm] int unreadChats = 0,
        [FromForm] int newLeads = 0,
        [FromForm] int qualifiedLeads = 0,
        [FromForm] int followUp = 0,
        [FromForm] int calls = 0,
        [FromForm] int potential = 0,
        [FromForm] int walkIns = 0,
        [FromForm] int conversion = 0,
        [FromForm] string? textContent = null,
        List<IFormFile>? files = null)
    {
        // Matches the mobile counter's own 3-digit typing limit — the UI can only ever
        // produce 0-999, so a raw API call claiming more than that is not a real report,
        // just an unbounded number nothing downstream (analytics, totals) expects.
        var values = new[] { unreadChats, newLeads, qualifiedLeads, followUp, calls, potential, walkIns, conversion };
        if (values.Any(v => v < 0 || v > 999))
        {
            return BadRequest(new ApiError { Message = "Values must be between 0 and 999." });
        }

        if (files is not null)
        {
            foreach (var file in files)
            {
                if (file.Length > MaxFileSizeBytes)
                {
                    return BadRequest(new ApiError { Message = $"\"{file.FileName}\" is too large (max 10 MB per file)." });
                }
                if (FileSafety.IsDangerous(file.FileName) || await FileSafety.HasDangerousContentAsync(file))
                {
                    return BadRequest(new ApiError { Message = $"\"{file.FileName}\" can't be attached — that file type isn't allowed." });
                }
            }
        }

        var userId = GetUserId();
        var today = DateTimeExtensions.PakistanToday();
        var attendance = await _db.Attendances
            .Include(a => a.Report)
            .ThenInclude(r => r!.Files)
            .FirstOrDefaultAsync(a => a.UserId == userId && a.Date == today);

        if (attendance is null)
        {
            return BadRequest(new ApiError { Message = "No attendance found for today. Please log in again." });
        }

        var report = attendance.Report;
        if (report is null)
        {
            report = new Report { UserId = userId, AttendanceId = attendance.Id, SubmittedAt = DateTime.UtcNow };
            attendance.Report = report;
            _db.Reports.Add(report);
            attendance.ReportSubmitted = true;
        }
        else
        {
            report.LastEditedAt = DateTime.UtcNow;
        }

        report.UnreadChats = unreadChats;
        report.NewLeads = newLeads;
        report.QualifiedLeads = qualifiedLeads;
        report.FollowUp = followUp;
        report.Calls = calls;
        report.Potential = potential;
        report.WalkIns = walkIns;
        report.Conversion = conversion;
        report.TextContent = textContent;

        if (files is not null)
        {
            foreach (var file in files)
            {
                using var stream = new MemoryStream();
                await file.CopyToAsync(stream);
                report.Files.Add(new ReportFile
                {
                    FileName = file.FileName,
                    ContentType = file.ContentType,
                    FileData = stream.ToArray()
                });
            }
        }

        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("reports");

        return Ok(ToResponse(report, attendance, today));
    }

    [HttpGet("mine")]
    public async Task<ActionResult<List<ReportResponse>>> Mine()
    {
        var userId = GetUserId();
        var today = DateTimeExtensions.PakistanToday();
        // Employees only ever see their own last full calendar month plus the
        // current one — the unrestricted date-range view is an Admin/Auditor
        // capability (see AdminController.Reports). This is deliberately the
        // 1st of LAST month, not "today minus 30 days": a rolling 30-day
        // window silently cuts off the first third of "last month" whenever
        // today isn't near a month's end (e.g. on the 12th, a rolling window
        // only reaches back to the 12th of last month — anything filed
        // earlier in that month, which the employee would still call "last
        // month", was invisible here even though it was never deleted).
        var earliest = new DateOnly(today.Year, today.Month, 1).AddMonths(-1);
        var reports = await _db.Reports
            .Include(r => r.Attendance)
            .Include(r => r.Files)
            .Where(r => r.UserId == userId && r.Attendance!.Date >= earliest)
            .ToListAsync();

        return Ok(reports
            .OrderByDescending(r => r.Attendance!.Date)
            .Select(r => ToResponse(r, r.Attendance!, today))
            .ToList());
    }

    /// Lets an employee re-download a file they themselves attached earlier.
    [HttpGet("files/{id:int}")]
    public async Task<IActionResult> DownloadFile(int id)
    {
        var file = await _db.ReportFiles.Include(f => f.Report).FirstOrDefaultAsync(f => f.Id == id);
        if (file is null || file.Report is null || file.Report.UserId != GetUserId())
        {
            return NotFound();
        }

        return File(file.FileData, file.ContentType ?? "application/octet-stream", file.FileName);
    }

    private static ReportResponse ToResponse(Report r, Attendance attendance, DateOnly today) => new()
    {
        Id = r.Id,
        Date = attendance.Date,
        UnreadChats = r.UnreadChats,
        NewLeads = r.NewLeads,
        QualifiedLeads = r.QualifiedLeads,
        FollowUp = r.FollowUp,
        Calls = r.Calls,
        Potential = r.Potential,
        WalkIns = r.WalkIns,
        Conversion = r.Conversion,
        TextContent = r.TextContent,
        Files = r.Files
            .Select(f => new ReportFileResponse { Id = f.Id, FileName = f.FileName, UploadedAt = f.UploadedAt })
            .ToList(),
        SubmittedAt = r.SubmittedAt,
        LastEditedAt = r.LastEditedAt,
        CheckInTime = attendance.CheckInTime,
        CheckOutTime = attendance.CheckOutTime,
        IsEditable = attendance.Date == today
    };

    private int GetUserId() =>
        int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
