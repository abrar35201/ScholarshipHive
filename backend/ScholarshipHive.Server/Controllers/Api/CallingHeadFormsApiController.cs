using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
using System.Text.Json;
namespace ScholarshipHive.Server.Controllers.Api;

[ApiController, Route("api/calling-head-forms")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "HeadOfCounselors")]
public sealed class CallingHeadFormsApiController : ControllerBase
{
    private readonly AppDbContext _db;
    public CallingHeadFormsApiController(AppDbContext db) => _db = db;
    private async Task<bool> AllowedAsync() =>
        int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) &&
        await _db.Users.AsNoTracking().AnyAsync(u => u.Id == id && u.Role == UserRole.HeadOfCounselors && u.IsActive && u.IsApproved);
    private IQueryable<CallingFormEntry> Records() => _db.CallingFormEntries.Where(e =>
        e.CreatedByUser.Role == UserRole.Employee && e.CreatedByUser.Department == EmployeeDepartment.Calling);

    [HttpGet]
    public async Task<IActionResult> Index()
    {
        if (!await AllowedAsync()) return Forbid();
        var entries = await Records().AsNoTracking().OrderByDescending(e => e.CreatedAt).Take(250)
            .Select(e => new { e.Id, e.ApplicantName, e.Phone, e.Email, e.TemplateId, e.CreatedAt,
                EmployeeName = e.CreatedByUser.FullName, Shared = e.PublicShareTokenHash != null }).ToListAsync();
        return Ok(entries);
    }
    [HttpGet("{id:int}")]
    public async Task<IActionResult> Detail(int id)
    {
        if (!await AllowedAsync()) return Forbid();
        var entry = await Records().AsNoTracking().Include(e => e.CreatedByUser).FirstOrDefaultAsync(e => e.Id == id);
        if (entry == null) return NotFound();
        return Ok(new {entry.Id, entry.ApplicantName, entry.Phone, entry.Email, entry.TemplateId,
            entry.CreatedAt, EmployeeName = entry.CreatedByUser.FullName,
            Answers = JsonSerializer.Deserialize<Dictionary<string, string>>(entry.AnswersJson),
            Shared = entry.PublicShareTokenHash != null});
    }
    [HttpPost("{id:int}/share")]
    public async Task<IActionResult> Share(int id)
    {
        if (!await AllowedAsync()) return Forbid();
        var entry = await Records().FirstOrDefaultAsync(e => e.Id == id);
        if (entry == null) return NotFound();
        var token = CallingFormSharing.CreateToken();
        entry.PublicShareTokenHash = CallingFormSharing.HashToken(token);
        entry.PublicShareCreatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { url = CallingFormSharing.Link(Request, token), message = "New private link created. Older links are now invalid." });
    }
    [HttpPost("{id:int}/revoke")]
    public async Task<IActionResult> Revoke(int id)
    {
        if (!await AllowedAsync()) return Forbid();
        var entry = await Records().FirstOrDefaultAsync(e => e.Id == id);
        if (entry == null) return NotFound();
        entry.PublicShareTokenHash = null;
        entry.PublicShareCreatedAt = null;
        await _db.SaveChangesAsync();
        return Ok(new { message = "Public share link revoked." });
    }
}
