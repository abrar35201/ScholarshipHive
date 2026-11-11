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
    [HttpGet("/Reception/CreateConsent")]
    public async Task<IActionResult> CreateConsent(int? visitorId)
    {
        var visitor = visitorId.HasValue ? await _db.VisitorRecords.FindAsync(visitorId.Value) : null;
        if (visitorId.HasValue && visitor is null) return NotFound();
        ViewBag.Visitor = visitor;
        return View(new ReceptionConsent {
            VisitorRecordId = visitor?.Id,
            ClientFullName = visitor?.FullName ?? "",
            PhoneNumber = visitor?.Contact ?? "",
            QualificationDetails = visitor?.Qualification ?? "",
            CounselorName = visitor?.Counsellor ?? ""
        });
    }

    [HttpPost("/Reception/CreateConsent"), ValidateAntiForgeryToken]
    public async Task<IActionResult> CreateConsent(ReceptionConsent form)
    {
        if (!ModelState.IsValid || form.TotalPackageFee < 0)
        {
            if (form.TotalPackageFee < 0) ModelState.AddModelError(nameof(form.TotalPackageFee), "Fee cannot be negative.");
            return View(form);
        }
        if (form.VisitorRecordId.HasValue && !await _db.VisitorRecords.AnyAsync(v => v.Id == form.VisitorRecordId.Value))
            return BadRequest("Linked visitor does not exist.");
        var record = new ReceptionConsent {
            VisitorRecordId = form.VisitorRecordId,
            ClientFullName = form.ClientFullName.Trim(), FamilyName = form.FamilyName,
            Gender = form.Gender, DomicileCity = form.DomicileCity, CnicNumber = form.CnicNumber,
            PhoneNumber = form.PhoneNumber, PassportNumber = form.PassportNumber,
            FullAddress = form.FullAddress, QualificationDetails = form.QualificationDetails,
            PolicyVariant = form.PolicyVariant, TotalPackageFee = form.TotalPackageFee,
            CounselorName = form.CounselorName, Status = "Draft",
            CreatedByUserId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!)
        };
        _db.ReceptionConsents.Add(record); await _db.SaveChangesAsync();
        TempData["Success"] = "Consent draft saved.";
        return Redirect("/Reception/Consents");
    }
    [HttpGet("/Reception/PrintConsent/{id:int}")]
    public async Task<IActionResult> PrintConsent(int id)
    {
        var consent=await _db.ReceptionConsents.FindAsync(id);
        return consent == null ? NotFound() : View(consent);
    }
    [HttpGet("/Reception/Consents")]
    public async Task<IActionResult> Consents() => View(await _db.ReceptionConsents
       .OrderByDescending(c => c.CreatedAt).Take(200).ToListAsync());
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
