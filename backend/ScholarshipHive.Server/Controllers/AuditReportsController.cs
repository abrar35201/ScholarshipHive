using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnly")]
public class AuditReportsController : Controller
{
    private readonly AppDbContext _db;

    public AuditReportsController(AppDbContext db)
    {
        _db = db;
    }

    public async Task<IActionResult> Index()
    {
        var reports = await _db.AuditReports
            .Include(a => a.AuditorUser)
            .Include(a => a.Files)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();

        return View(reports);
    }

    public async Task<IActionResult> Details(int id)
    {
        var report = await _db.AuditReports
            .Include(a => a.AuditorUser)
            .Include(a => a.Files)
            .FirstOrDefaultAsync(a => a.Id == id);

        if (report is null) return NotFound();
        return View(report);
    }

    public async Task<IActionResult> Download(int fileId)
    {
        var file = await _db.AuditReportFiles.FindAsync(fileId);
        if (file is null) return NotFound();

        return File(file.FileData, file.ContentType ?? "application/octet-stream", file.FileName);
    }
}
