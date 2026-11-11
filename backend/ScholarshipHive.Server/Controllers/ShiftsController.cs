using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

/// Lets an admin set each employee's shift window — either one at a time, or
/// in bulk for a whole department — since attendance lateness is now judged
/// against each person's own ShiftStartTime (see DateTimeExtensions.IsLateFor)
/// instead of one fixed cutoff for everyone.
[Authorize(Policy = "AdminOnly")]
public class ShiftsController : Controller
{
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _realtime;
    private readonly FcmPushService _fcm;

    public ShiftsController(AppDbContext db, RealtimeNotifier realtime, FcmPushService fcm)
    {
        _db = db;
        _realtime = realtime;
        _fcm = fcm;
    }

    public async Task<IActionResult> Index(EmployeeDepartment? department)
    {
        var query = _db.Users.Where(u => u.Role == UserRole.Employee).AsQueryable();
        if (department.HasValue) query = query.Where(u => u.Department == department.Value);

        var employees = await query.OrderBy(u => u.Department).ThenBy(u => u.Username).ToListAsync();
        ViewBag.SelectedDepartment = department;
        return View(employees);
    }

    /// One row's own Save button — a manual, one-off edit for a single person.
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SetForUser(int userId, TimeOnly shiftStartTime, TimeOnly shiftEndTime, ShiftType shiftType)
    {
        var user = await _db.Users.FindAsync(userId);
        if (user is null) return NotFound();

        user.ShiftStartTime = shiftStartTime;
        user.ShiftEndTime = shiftEndTime;
        user.ShiftType = shiftType;
        _db.UserNotices.Add(new UserNotice { UserId=user.Id, Title="Your shift was updated",
            Body=$"Your new {shiftType} shift is {shiftStartTime:HH:mm}–{shiftEndTime:HH:mm}.",
            ActorName=User.Identity?.Name ?? "Administrator" });
        await _db.SaveChangesAsync();
        if (!string.IsNullOrWhiteSpace(user.FcmToken)) await _fcm.SendNotificationAsync(user.FcmToken, "Shift timing changed", $"New shift: {shiftStartTime:HH:mm}–{shiftEndTime:HH:mm}");
        await _realtime.NotifyAsync("users");

        TempData["Success"] = $"Shift updated for '{user.Username}'.";
        return RedirectToAction(nameof(Index));
    }

    /// The top bulk-apply bar — either every active employee in a chosen
    /// department, or (when UserIds is non-empty) exactly the checked rows,
    /// regardless of department. Never both at once: an explicit UserIds
    /// selection always wins over Department, since a checked-row selection
    /// is a more deliberate choice than whatever department filter happens to
    /// be showing.
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SetBulk(ShiftAssignmentViewModel model)
    {
        var query = _db.Users.Where(u => u.Role == UserRole.Employee).AsQueryable();
        query = model.UserIds.Count > 0
            ? query.Where(u => model.UserIds.Contains(u.Id))
            : model.Department.HasValue
                ? query.Where(u => u.Department == model.Department.Value)
                : query; // Neither a selection nor a department chosen — applies to every employee.

        var affected = await query.ToListAsync();
        foreach (var u in affected)
        {
            u.ShiftStartTime = model.ShiftStartTime;
            u.ShiftEndTime = model.ShiftEndTime;
            u.ShiftType = model.ShiftType;
            _db.UserNotices.Add(new UserNotice { UserId=u.Id, Title="Your shift was updated",
                Body=$"Your new {model.ShiftType} shift is {model.ShiftStartTime:HH:mm}–{model.ShiftEndTime:HH:mm}.",
                ActorName=User.Identity?.Name ?? "Administrator" });
        }
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");

        foreach (var u in affected.Where(x => !string.IsNullOrWhiteSpace(x.FcmToken)))
            await _fcm.SendNotificationAsync(u.FcmToken!, "Shift timing changed", $"New shift: {model.ShiftStartTime:HH:mm}–{model.ShiftEndTime:HH:mm}");
        TempData["Success"] = $"Shift updated for {affected.Count} employee(s).";
        return RedirectToAction(nameof(Index), new { department = model.Department });
    }
}
