using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnly")]
public class AnalyticsController : Controller
{
    private readonly AnalyticsService _analytics;

    public AnalyticsController(AnalyticsService analytics)
    {
        _analytics = analytics;
    }

    public async Task<IActionResult> Index()
    {
        var data = await _analytics.ComputeAsync();
        return View(data);
    }
}
