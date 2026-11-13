using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers;

[Authorize(AuthenticationSchemes = CookieAuthenticationDefaults.AuthenticationScheme, Roles = "HeadOfCounselors")]
[Route("CallingHeadForms")]
public class CallingHeadFormsController : Controller
{
    private readonly AppDbContext _db;
    public CallingHeadFormsController(AppDbContext db) => _db = db;
    private async Task<bool> AllowedAsync() => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) &&
        await _db.Users.AsNoTracking().AnyAsync(u => u.Id == id && u.Role == UserRole.HeadOfCounselors && u.IsApproved && u.IsActive);
    private IQueryable<CallingFormEntry> Records() => _db.CallingFormEntries.Where(e =>
        e.CreatedByUser.Role == UserRole.Employee && e.CreatedByUser.Department == EmployeeDepartment.Calling);
    [HttpGet("")]
    public async Task<IActionResult> Index()
    {
        if (!await AllowedAsync()) return Forbid();
        return View(await Records().AsNoTracking().Include(e => e.CreatedByUser).OrderByDescending(e => e.CreatedAt).Take(250).ToListAsync());
    }
    [HttpGet("Details/{id:int}")]
    public async Task<IActionResult> Details(int id)
    {
        if (!await AllowedAsync()) return Forbid();
        var entry = await Records().AsNoTracking().Include(e => e.CreatedByUser).FirstOrDefaultAsync(e => e.Id == id);
        if (entry == null) return NotFound();
        return View(entry);
    }
    [HttpPost("Share/{id:int}"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Share(int id)
    {
        if (!await AllowedAsync()) return Forbid();
        var entry = await Records().FirstOrDefaultAsync(e => e.Id == id);
        if (entry == null) return NotFound();
        var token = CallingFormSharing.CreateToken();
        entry.PublicShareTokenHash = CallingFormSharing.HashToken(token);
        entry.PublicShareCreatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        TempData["NewShareUrl"] = CallingFormSharing.Link(Request, token);
        return RedirectToAction(nameof(Details), new { id });
    }
    [HttpPost("Revoke/{id:int}"), ValidateAntiForgeryToken]
    public async Task<IActionResult> Revoke(int id)
    {
        if (!await AllowedAsync()) return Forbid();
        var entry = await Records().FirstOrDefaultAsync(e => e.Id == id);
        if (entry == null) return NotFound();
        entry.PublicShareTokenHash = null;
        entry.PublicShareCreatedAt = null;
        await _db.SaveChangesAsync();
        TempData["Success"] = "Link revoked.";
        return RedirectToAction(nameof(Details), new { id });
    }
}
