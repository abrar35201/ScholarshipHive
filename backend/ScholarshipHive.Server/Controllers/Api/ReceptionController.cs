using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers.Api;
public class VisitorDto
{
    [Required, MaxLength(120)] public string FullName { get; set; } = "";
    [MaxLength(40)] public string? Contact { get; set; }
    [MaxLength(150)] public string? Email { get; set; }
    [MaxLength(100)] public string? Qualification { get; set; }
    [MaxLength(100)] public string? Country { get; set; }
    [MaxLength(100)] public string? Program { get; set; }
    [MaxLength(40)] public string? InquiryType { get; set; }
    [MaxLength(100)] public string? Counsellor { get; set; }
    [MaxLength(1000)] public string? Remarks { get; set; }
}
[ApiController]
[Route("api/reception")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Receptionist,Admin,Auditor,SuperAdmin,Owner,CountryHead,HeadOfMarketing,HeadOfProcessing")]
public class ReceptionController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly RealtimeNotifier _realtime;
    public ReceptionController(AppDbContext db, RealtimeNotifier realtime) { _db = db; _realtime = realtime; }
    [HttpGet("visitors")]
    public async Task<IActionResult> List() => Ok(await _db.VisitorRecords
        .OrderByDescending(v => v.CheckInTime).Take(100).ToListAsync());
    [HttpPost("visitors")]
    public async Task<IActionResult> Create([FromBody] VisitorDto input)
    {
        var error = VisitorInputRules.Error(input.FullName, input.Contact, input.Email);
        if (error != null) return BadRequest(new { message = error });
        var visitor = new VisitorRecord {
            FullName = input.FullName.Trim(), Contact = input.Contact?.Trim(), Email = input.Email?.Trim(),
            Qualification = input.Qualification, Country = input.Country, Program = input.Program,
            InquiryType = input.InquiryType, Counsellor = input.Counsellor, Remarks = input.Remarks,
            RegisteredByUserId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!)
        };
        _db.VisitorRecords.Add(visitor);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("visitors");
        return Ok(new { visitor.Id, message = "Visitor checked in." });
    }
    [HttpPost("visitors/{id:int}/checkout")]
    public async Task<IActionResult> Checkout(int id)
    {
        var visitor = await _db.VisitorRecords.FindAsync(id);
        if (visitor == null) return NotFound();
        if (visitor.CheckOutTime != null) return Conflict(new { message = "Already checked out." });
        visitor.CheckOutTime = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("visitors");
        return Ok(new { visitor.Id, message = "Visitor checked out." });
    }
}
