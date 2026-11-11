using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
namespace ScholarshipHive.Server.Controllers;
[Authorize(Policy = "AdminOnly")]
public class LeavesController : Controller
{
    private readonly AppDbContext _db;
    public LeavesController(AppDbContext db) => _db = db;
    [HttpGet]
    public async Task<IActionResult> Index() => View(await _db.LeaveRequests.Include(l => l.User)
      .OrderBy(l => l.Status == "Pending" ? 0 : 1).ThenByDescending(l => l.AppliedAt).Take(200).ToListAsync());
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Decide(int id, string decision)
    {
        if (decision is not ("Approved" or "Rejected")) return BadRequest();
        var leave = await _db.LeaveRequests.FindAsync(id);
        if (leave == null) return NotFound();
        if (leave.Status != "Pending") return Conflict("Already decided.");
        leave.Status = decision; leave.ReviewedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return RedirectToAction(nameof(Index));
    }
}
