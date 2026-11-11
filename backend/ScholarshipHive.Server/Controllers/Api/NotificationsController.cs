using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
namespace ScholarshipHive.Server.Controllers.Api;
[ApiController, Route("api/notifications")]
[Authorize(AuthenticationSchemes=JwtBearerDefaults.AuthenticationScheme, Roles="Admin,SuperAdmin,Owner,CountryHead,Auditor")]
public class NotificationsController : ControllerBase
{
    private readonly AppDbContext _db;
    public NotificationsController(AppDbContext db) => _db=db;
    [HttpGet("pending")]
    public async Task<IActionResult> Pending()
    {
        var leaves=await _db.LeaveRequests.Include(x=>x.User).Where(x=>x.Status=="Pending")
            .OrderByDescending(x=>x.AppliedAt).Take(30).Select(x=>new{ x.Id, Employee=x.User!.FullName, Type=x.LeaveType, Date=x.LeaveDate, Category="Leave" }).ToListAsync();
        var shifts=await _db.ShiftChangeRequests.Include(x=>x.User).Where(x=>x.Status=="Pending")
            .OrderByDescending(x=>x.CreatedAt).Take(30).Select(x=>new{ x.Id, Employee=x.User!.FullName, Type=x.ShiftType.ToString(), Date=x.CreatedAt, Category="Shift" }).ToListAsync();
        return Ok(new {Count=leaves.Count+shifts.Count, Leaves=leaves, Shifts=shifts});
    }
}
