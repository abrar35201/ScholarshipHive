using System.Diagnostics;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnly")]
public class HomeController : Controller
{
    private readonly AppDbContext _db;
    private readonly DashboardAnalyticsService _analytics;
    private readonly FcmPushService _fcm;

    public HomeController(AppDbContext db, DashboardAnalyticsService analytics, FcmPushService fcm)
    {
        _db = db;
        _analytics = analytics;
        _fcm = fcm;
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public async Task<IActionResult> Index(string period = "day")
    {
        if (period is not ("day" or "week" or "month")) period = "day";
        var today = DateTimeExtensions.PakistanToday();

        // Computed first so CheckedInNow below can reuse its result instead of
        // re-querying the same "today, not checked out" count a second time.
        var analytics = await _analytics.ComputeAsync(period);

        var model = new DashboardViewModel
        {
            TotalUsers = await _db.Users.CountAsync(),
            CheckedInNow = analytics.CheckedInNow,
            ReportsToday = await _db.Attendances.CountAsync(a => a.Date == today && a.ReportSubmitted),
            ConfiguredRouters = await _db.AllowedRouters.CountAsync(r => r.IsActive),
            RecentAttendance = await _db.Attendances
                .Include(a => a.User)
                .OrderByDescending(a => a.CheckInTime)
                .Take(10)
                .ToListAsync(),
            Period = period,
        };

        model.WeeklyHeadcount = analytics.WeeklyHeadcount;
        model.ArrivalCurve = analytics.ArrivalCurve;
        model.PresentOnTimeToday = analytics.PresentOnTimeToday;
        model.LateToday = analytics.LateToday;
        model.AbsentToday = analytics.AbsentToday;
        model.ShiftHealth = analytics.ShiftHealth;
        model.TotalActiveEmployees = analytics.TotalActiveEmployees;
        model.AwayCount = analytics.AwayCount;
        model.AverageArrivalLabel = analytics.AverageArrivalLabel;
        model.AverageArrivalSublabel = analytics.AverageArrivalSublabel;
        model.AverageArrivalTrendMinutes = analytics.AverageArrivalTrendMinutes;
        model.ReportsFiledRate = analytics.ReportsFiledRate;
        model.ReportsFiledFraction = analytics.ReportsFiledFraction;
        model.ReportsFiledTrendPct = analytics.ReportsFiledTrendPct;
        model.PunctualityRatePct = analytics.PunctualityRatePct;
        model.PunctualityRateTrendPct = analytics.PunctualityRateTrendPct;
        model.Roster = analytics.Roster;
        model.DailyBreakdown = analytics.DailyBreakdown;
        model.PushNotificationsEnabled = _fcm.IsEnabled;

        return View(model);
    }

    [AllowAnonymous]
    public IActionResult Privacy()
    {
        return View();
    }

    /// Play Console's Data Safety form requires a public URL explaining how a
    /// user requests their account/data be deleted — this app has no
    /// self-service deletion (removing an employee's attendance history would
    /// break company recordkeeping an admin is responsible for), so this
    /// documents the admin-mediated request process instead, which is what
    /// Google's own guidance allows for an internal/enterprise app like this one.
    [AllowAnonymous]
    public IActionResult DeleteAccount()
    {
        return View();
    }

    [AllowAnonymous]
    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }
}
