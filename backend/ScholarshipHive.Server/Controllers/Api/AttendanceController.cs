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

/// An employee's OWN attendance history. Deliberately Present/Absent only —
/// exact check-in/check-out timings stay Admin/Auditor-only (see
/// AdminController.Attendance and UsersController.DayHistory for those).
[ApiController]
[Route("api/attendance")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
public class AttendanceController : ControllerBase
{
    private readonly AppDbContext _db;

    public AttendanceController(AppDbContext db)
    {
        _db = db;
    }

    [HttpGet("mine")]
    public async Task<ActionResult<List<MyAttendanceDayDto>>> Mine()
    {
        var userId = GetUserId();
        var user = await _db.Users.FindAsync(userId);
        if (user is null) return Unauthorized();

        var today = DateTimeExtensions.PakistanToday();
        // Start of LAST calendar month, not "today minus 30 days" — a rolling
        // window silently cuts off the first part of "last month" whenever
        // today isn't near a month's end (see the matching fix/comment in
        // ReportsController.Mine for the full reasoning).
        var since = new DateOnly(today.Year, today.Month, 1).AddMonths(-1);

        var checkInByDate = (await _db.Attendances
            .Where(a => a.UserId == userId && a.Date >= since && a.Date <= today)
            .Select(a => new { a.Date, a.CheckInTime })
            .ToListAsync())
            .ToDictionary(a => a.Date, a => a.CheckInTime);

        var result = new List<MyAttendanceDayDto>();
        for (var d = today; d >= since; d = d.AddDays(-1))
        {
            var hasAttendance = checkInByDate.TryGetValue(d, out var checkInTime);
            // Same vocabulary as the admin single-user calendar (AttendanceController,
            // web) — a day off is a day off, but still checking in that day is "extra"
            // time worked, not just an ordinary present/absent working day. Saturday is
            // a working day for everyone except this user's own department (Interns).
            var status = d.DayOfWeek.IsWeekendOff(user.Department == EmployeeDepartment.Interns)
                ? (hasAttendance ? "Extra" : "Weekend")
                : (hasAttendance ? (checkInTime.IsLateFor(user.ShiftStartTime) ? "Late" : "Present") : "Absent");
            result.Add(new MyAttendanceDayDto { Date = d, Present = hasAttendance, Status = status });
        }

        return Ok(result);
    }

    private int GetUserId() =>
        int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
