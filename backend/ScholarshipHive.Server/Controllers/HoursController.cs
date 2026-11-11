using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

/// Every employee's real accumulated presence time (see AttendanceDurationService) —
/// a list of totals over a date range (default: the last calendar month through
/// today), drilling into a day-by-day breakdown per person.
[Authorize(Policy = "AdminOnly")]
public class HoursController : Controller
{
    private readonly AppDbContext _db;
    private readonly AttendanceDurationService _duration;

    public HoursController(AppDbContext db, AttendanceDurationService duration)
    {
        _db = db;
        _duration = duration;
    }

    public async Task<IActionResult> Index(DateTime? from, DateTime? to)
    {
        var today = DateTimeExtensions.PakistanToday();
        var effectiveTo = to.HasValue ? DateOnly.FromDateTime(to.Value) : today;
        var effectiveFrom = from.HasValue ? DateOnly.FromDateTime(from.Value) : effectiveTo.AddMonths(-1);

        var employees = await _db.Users.Where(u => (u.Role != UserRole.Admin || u.Username.ToLower() != "admin")).OrderBy(u => u.FullName).ToListAsync();
        var byUser = await _duration.ComputeManyAsync(employees.Select(u => u.Id).ToList(), effectiveFrom, effectiveTo, DateTime.UtcNow);

        var rows = employees.Select(u => new HoursListEntryDto
        {
            UserId = u.Id,
            Name = u.FullName,
            Department = u.Role == UserRole.Employee ? u.Department.ToString() :
                u.Role == UserRole.Receptionist ? "Reception" : AccessRules.DisplayRole(u.Role),
            TotalMinutes = byUser[u.Id].Values.Sum(d => d.Minutes),
            GapMinutes = byUser[u.Id].Values.Sum(d => d.GapMinutes)
        }).OrderByDescending(e => e.TotalMinutes).ToList();

        ViewBag.FromDate = effectiveFrom.ToString("yyyy-MM-dd");
        ViewBag.ToDate = effectiveTo.ToString("yyyy-MM-dd");
        return View(rows);
    }

    /// Wipes the entire LoginHistory audit trail — the raw check-in/check-out
    /// event log AttendanceDurationService pairs up into the Hours totals
    /// above, and the same table backing each user's "History" tab. There's no
    /// separate "Hours data" to selectively clear; it's computed fresh from
    /// this table every time. Deliberately not soft-deletable or scoped to a
    /// date range — this is a full reset, triggered by an admin who already
    /// understands that.
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> ClearHistory()
    {
        // ExecuteDeleteAsync bypasses SaveChanges and its automatic AuditEvent hook.
        // Record this destructive admin action in the same database transaction.
        await using var transaction = await _db.Database.BeginTransactionAsync();
        var removedCount = await _db.LoginHistories.ExecuteDeleteAsync();
        _db.AuditEvents.Add(new AuditEvent
        {
            Actor = User.Identity?.Name ?? "Authenticated Admin",
            EntityType = nameof(LoginHistory),
            Action = "ClearHistory",
            EntityKey = "All",
            Details = $"Deleted {removedCount} attendance history event(s)",
            AtUtc = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();
        return RedirectToAction(nameof(Index));
    }

    public async Task<IActionResult> Detail(int id, DateTime? from, DateTime? to)
    {
        var user = await _db.Users.FindAsync(id);
        if (user is null) return NotFound();

        var today = DateTimeExtensions.PakistanToday();
        var effectiveTo = to.HasValue ? DateOnly.FromDateTime(to.Value) : today;
        var effectiveFrom = from.HasValue ? DateOnly.FromDateTime(from.Value) : effectiveTo.AddMonths(-1);

        var byDay = await _duration.ComputeAsync(id, effectiveFrom, effectiveTo, DateTime.UtcNow);
        var days = new List<HoursDayDto>();
        for (var d = effectiveTo; d >= effectiveFrom; d = d.AddDays(-1))
        {
            var dur = byDay.GetValueOrDefault(d, new DayDuration(0, false));
            days.Add(new HoursDayDto { Date = d, Minutes = dur.Minutes, GapMinutes = dur.GapMinutes, StillOpen = dur.StillOpen });
        }

        // Explicit activity timeline for completed and interrupted office sessions.
        // No new attendance state or schema: these are the existing audit events.
        var start = DateTime.SpecifyKind(effectiveFrom.ToDateTime(TimeOnly.MinValue).AddHours(2), DateTimeKind.Utc);
        var end = DateTime.SpecifyKind(effectiveTo.AddDays(1).ToDateTime(TimeOnly.MinValue).AddHours(2), DateTimeKind.Utc);
        var events = await _db.LoginHistories
            .Where(h => h.UserId == id && h.Timestamp >= start && h.Timestamp < end)
            .OrderBy(h => h.Timestamp).ToListAsync();
        ViewBag.EventsByDay = events.GroupBy(h => DateTimeExtensions.PakistanDateOf(h.Timestamp))
            .ToDictionary(g => g.Key, g => g.ToList());

        ViewBag.UserId = id;
        ViewBag.UserName = user.FullName;
        ViewBag.FromDate = effectiveFrom.ToString("yyyy-MM-dd");
        ViewBag.ToDate = effectiveTo.ToString("yyyy-MM-dd");
        ViewBag.TotalMinutes = days.Sum(d => d.Minutes);
        ViewBag.TotalGapMinutes = days.Sum(d => d.GapMinutes);
        return View(days);
    }
}
