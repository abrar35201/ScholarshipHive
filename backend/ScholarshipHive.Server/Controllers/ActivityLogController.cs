using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;

namespace ScholarshipHive.Server.Controllers;

[Authorize(AuthenticationSchemes = CookieAuthenticationDefaults.AuthenticationScheme, Roles = "Admin,Owner,SuperAdmin,Auditor")]
public class ActivityLogController : Controller
{
    private readonly AppDbContext _db;
    public ActivityLogController(AppDbContext db) => _db = db;
    public async Task<IActionResult> Index(string? actor, string? action, string? entity, DateTime? fromUtc, DateTime? toUtc)
    {
        var query = _db.AuditEvents.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(actor)) query = query.Where(x => x.Actor.Contains(actor));
        if (!string.IsNullOrWhiteSpace(action)) query = query.Where(x => x.Action == action);
        if (!string.IsNullOrWhiteSpace(entity)) query = query.Where(x => x.EntityType.Contains(entity));
        if (fromUtc.HasValue) query = query.Where(x => x.AtUtc >= DateTime.SpecifyKind(fromUtc.Value, DateTimeKind.Utc));
        if (toUtc.HasValue) query = query.Where(x => x.AtUtc < DateTime.SpecifyKind(toUtc.Value.Date.AddDays(1), DateTimeKind.Utc));
        ViewBag.ActorFilter = actor;
        ViewBag.ActionFilter = action;
        ViewBag.EntityFilter = entity;
        ViewBag.FromFilter = fromUtc?.ToString("yyyy-MM-dd");
        ViewBag.ToFilter = toUtc?.ToString("yyyy-MM-dd");
        return View(await query.OrderByDescending(x => x.AtUtc).Take(500).ToListAsync());
    }
}
