using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers;

[AllowAnonymous]
[Route("shared/calling-form")]
public sealed class PublicCallingFormController : Controller
{
    private readonly AppDbContext _db;
    public PublicCallingFormController(AppDbContext db) => _db = db;
    [HttpGet("{token}")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<IActionResult> ViewForm(string token)
    {
        Response.Headers["Cache-Control"] = "no-store";
        Response.Headers["Pragma"] = "no-cache";
        Response.Headers["X-Robots-Tag"] = "noindex, nofollow, noarchive";
        Response.Headers["Referrer-Policy"] = "no-referrer";
        Response.Headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
        if (!CallingFormSharing.ValidToken(token)) return NotFound();
        var hash = CallingFormSharing.HashToken(token);
        var entry = await _db.CallingFormEntries.AsNoTracking().FirstOrDefaultAsync(e => e.PublicShareTokenHash == hash);
        if (entry == null) return NotFound();
        ViewBag.Template = CallingFormCatalog.Find(entry.TemplateId);
        ViewBag.Answers = JsonSerializer.Deserialize<Dictionary<string, string>>(entry.AnswersJson) ?? new();
        return View(entry);
    }
}
