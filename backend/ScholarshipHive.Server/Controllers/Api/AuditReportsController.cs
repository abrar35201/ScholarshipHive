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

/// Audit reports are the Auditor's own work product — compiled findings about
/// everyone else's data — not the day-to-day per-employee Report. An Auditor
/// submits them; an Admin (or another Auditor) only ever reads them.
[ApiController]
[Route("api/audit-reports")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin,Auditor")]
public class AuditReportsController : ControllerBase
{
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;
    private const long MaxTotalRequestBytes = 60 * 1024 * 1024;

    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _realtime;

    public AuditReportsController(AppDbContext db, RealtimeNotifier realtime)
    {
        _db = db;
        _realtime = realtime;
    }

    [HttpPost]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Auditor")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(MaxTotalRequestBytes)]
    public async Task<ActionResult<AuditReportResponse>> Submit(
        [FromForm] string title,
        [FromForm] string? textContent,
        List<IFormFile>? files = null)
    {
        if (string.IsNullOrWhiteSpace(title))
        {
            return BadRequest(new ApiError { Message = "Give this audit report a title first." });
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

        var report = new AuditReport
        {
            AuditorUserId = GetUserId(),
            Title = title.Trim(),
            TextContent = textContent
        };

        if (files is not null)
        {
            foreach (var file in files)
            {
                using var stream = new MemoryStream();
                await file.CopyToAsync(stream);
                report.Files.Add(new AuditReportFile
                {
                    FileName = file.FileName,
                    ContentType = file.ContentType,
                    FileData = stream.ToArray()
                });
            }
        }

        _db.AuditReports.Add(report);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("auditReports");

        var user = await _db.Users.FindAsync(report.AuditorUserId);
        return Ok(ToResponse(report, user!.Username));
    }

    [HttpGet]
    public async Task<ActionResult<List<AuditReportResponse>>> List()
    {
        var reports = await _db.AuditReports
            .Include(a => a.AuditorUser)
            .Include(a => a.Files)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();

        return Ok(reports.Select(r => ToResponse(r, r.AuditorUser?.Username ?? "")).ToList());
    }

    [HttpGet("{id:int}")]
    public async Task<ActionResult<AuditReportResponse>> Details(int id)
    {
        var report = await _db.AuditReports
            .Include(a => a.AuditorUser)
            .Include(a => a.Files)
            .FirstOrDefaultAsync(a => a.Id == id);

        if (report is null) return NotFound();
        return Ok(ToResponse(report, report.AuditorUser?.Username ?? ""));
    }

    [HttpGet("files/{id:int}")]
    public async Task<IActionResult> DownloadFile(int id)
    {
        var file = await _db.AuditReportFiles.FindAsync(id);
        if (file is null) return NotFound();

        return File(file.FileData, file.ContentType ?? "application/octet-stream", file.FileName);
    }

    private static AuditReportResponse ToResponse(AuditReport r, string auditorUsername) => new()
    {
        Id = r.Id,
        AuditorUsername = auditorUsername,
        Title = r.Title,
        TextContent = r.TextContent,
        CreatedAt = r.CreatedAt,
        Files = r.Files
            .Select(f => new AuditReportFileResponse { Id = f.Id, FileName = f.FileName, UploadedAt = f.UploadedAt })
            .ToList()
    };

    private int GetUserId() =>
        int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
