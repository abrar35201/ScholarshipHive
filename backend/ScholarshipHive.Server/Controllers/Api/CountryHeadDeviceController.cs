using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers.Api;

[ApiController, Route("api/country-head/device")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "CountryHead")]
public sealed class CountryHeadDeviceController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _rt;
    public CountryHeadDeviceController(AppDbContext db, RealtimeNotifier rt) { _db = db; _rt = rt; }
    [HttpPost("employees/{id:int}/reset")]
    public async Task<IActionResult> Reset(int id)
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var currentId) ||
            !await _db.Users.AnyAsync(u => u.Id == currentId && u.Role == UserRole.CountryHead && u.IsActive && u.IsApproved)) return Forbid();
        var employee = await _db.Users.FirstOrDefaultAsync(u => u.Id == id && u.Role == UserRole.Employee && u.IsActive);
        if (employee == null) return NotFound();
        employee.HomeDeviceId = null;
        employee.LastDeviceId = null;
        employee.LastDeviceLoginAt = null;
        employee.FcmToken = null;
        await _db.SaveChangesAsync();
        await _rt.NotifyAsync("users");
        return Ok(new { message = "Employee phone reset; password and office network required next login." });
    }
}
