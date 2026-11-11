using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;

namespace ScholarshipHive.Server.Controllers.Api;

[ApiController]
[Route("api/user-notices")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
public sealed class UserNoticesController : ControllerBase
{
    private readonly AppDbContext _db;
    public UserNoticesController(AppDbContext db) => _db = db;
    [HttpGet]
    public async Task<IActionResult> Index()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return Unauthorized();
        return Ok(await _db.UserNotices.Where(n => n.UserId == id)
            .OrderByDescending(n => n.CreatedAt).Take(100)
            .Select(n => new { n.Id, n.Title, n.Body, n.ActorName, n.CreatedAt })
            .ToListAsync());
    }
}
