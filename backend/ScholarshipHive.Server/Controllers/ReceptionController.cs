using Microsoft.AspNetCore.Authorization;
using ScholarshipHive.Server.Services;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Identity;
using System.Security.Claims;
using ScholarshipHive.Server.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
namespace ScholarshipHive.Server.Controllers;
[Authorize(AuthenticationSchemes = CookieAuthenticationDefaults.AuthenticationScheme, Roles = "Admin,SuperAdmin,Owner,CountryHead,HeadOfMarketing,HeadOfProcessing,Auditor,Receptionist")]
public class ReceptionController : Controller
{
    private readonly AppDbContext _db;
    public ReceptionController(AppDbContext db) => _db = db;
    [HttpPost, ValidateAntiForgeryToken]
    [Authorize(Roles = "Receptionist,Admin,SuperAdmin,Owner")]
    public async Task<IActionResult> RegisterVisitor(string fullName, string contact, string? email,
        string? qualification, string? country, string? program, string? inquiryType,
        string? counsellor, string? remarks)
    {
        var error = VisitorInputRules.Error(fullName, contact, email);
        if (error != null) { TempData["Error"] = error; return RedirectToAction(nameof(Index)); }
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var actor)) return Forbid();
        _db.VisitorRecords.Add(new VisitorRecord {
            FullName = fullName.Trim(), Contact = contact.Trim(), Email = email?.Trim(),
            Qualification = qualification?.Trim(), Country = country?.Trim(), Program = program?.Trim(),
            InquiryType = inquiryType?.Trim(), Counsellor = counsellor?.Trim(), Remarks = remarks?.Trim(),
            RegisteredByUserId = actor
        });
        await _db.SaveChangesAsync();
        TempData["Success"] = "Visitor checked in.";
        return RedirectToAction(nameof(Index));
    }
    [HttpPost, ValidateAntiForgeryToken]
    [Authorize(Roles = "Receptionist,Admin,SuperAdmin,Owner")]
    public async Task<IActionResult> CheckoutVisitor(int id)
    {
        var visitor = await _db.VisitorRecords.FindAsync(id);
        if (visitor == null) return NotFound();
        if (visitor.CheckOutTime != null) { TempData["Error"] = "Visitor already checked out."; return RedirectToAction(nameof(Index)); }
        visitor.CheckOutTime = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        TempData["Success"] = "Visitor checked out.";
        return RedirectToAction(nameof(Index));
    }
    [HttpGet]
    public async Task<IActionResult> Index() => View(await _db.VisitorRecords
       .OrderByDescending(v => v.CheckInTime).Take(200).ToListAsync());
}
