using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(AuthenticationSchemes=CookieAuthenticationDefaults.AuthenticationScheme, Roles="Employee")]
[Route("CallingForms")]
public class CallingFormsController : Controller
{
    private readonly AppDbContext _db;
    private readonly IWebHostEnvironment _environment;
    public CallingFormsController(AppDbContext db, IWebHostEnvironment environment) { _db=db; _environment=environment; }
    private async Task<int?> CallingUserId()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return null;
        return await _db.Users.AsNoTracking().AnyAsync(u=>u.Id==id && u.Role==UserRole.Employee &&
            u.Department==EmployeeDepartment.Calling && u.IsActive && u.IsApproved) ? id : null;
    }
    [HttpGet("")]
    public async Task<IActionResult> Index()
    {
        var id=await CallingUserId(); if(!id.HasValue)return Forbid();
        ViewBag.Templates=CallingFormCatalog.All;
        return View(await _db.CallingFormEntries.AsNoTracking().Where(f=>f.CreatedByUserId==id.Value)
            .OrderByDescending(f=>f.CreatedAt).Take(100).ToListAsync());
    }
    [HttpGet("New/{templateId}")]
    public async Task<IActionResult> New(string templateId)
    {
        if(!(await CallingUserId()).HasValue)return Forbid();
        var template=CallingFormCatalog.Find(templateId);if(template==null)return NotFound();
        ViewBag.Template=template;ViewBag.Fields=CallingFormCatalog.Fields;
        return View();
    }
    [HttpPost("New/{templateId}"), ValidateAntiForgeryToken]
    [RequestFormLimits(ValueCountLimit=80)]
    public async Task<IActionResult> Create(string templateId,string applicantName,string phone,string? email)
    {
        var id=await CallingUserId();if(!id.HasValue)return Forbid();
        var template=CallingFormCatalog.Find(templateId);if(template==null)return NotFound();
        applicantName=(applicantName??"").Trim();phone=(phone??"").Trim();email=email?.Trim();
        if(applicantName.Length is <2 or >120 || phone.Length is <7 or >40 || email?.Length>150)
        {
            TempData["Error"]="Enter a valid applicant name and contact number.";
            return RedirectToAction(nameof(New),new{templateId});
        }
        var values=new Dictionary<string,string>();
        foreach(var key in CallingFormCatalog.Fields)
        {
            var raw=Request.Form["answer_"+key].ToString().Trim();
            if(raw.Length>350){TempData["Error"]="A field is too long.";return RedirectToAction(nameof(New),new{templateId});}
            if(raw.Length>0)values[key]=raw;
        }
        var json=JsonSerializer.Serialize(values);
        if(json.Length>14000)return BadRequest("Form is too large.");
        _db.CallingFormEntries.Add(new CallingFormEntry { CreatedByUserId=id.Value,TemplateId=templateId,
            ApplicantName=applicantName,Phone=phone,Email=email,AnswersJson=json,CreatedAt=DateTime.UtcNow });
        await _db.SaveChangesAsync();
        TempData["Success"]="Application draft saved. Review and sign the original agreement separately.";
        return RedirectToAction(nameof(Index));
    }
    [HttpGet("Details/{id:int}")]
    public async Task<IActionResult> Details(int id)
    {
        var owner=await CallingUserId();if(!owner.HasValue)return Forbid();
        var entry=await _db.CallingFormEntries.AsNoTracking().FirstOrDefaultAsync(x=>x.Id==id && x.CreatedByUserId==owner.Value);
        if(entry==null)return NotFound();
        ViewBag.Template=CallingFormCatalog.Find(entry.TemplateId);
        return View(entry);
    }
    [HttpGet("Template/{templateId}")]
    public async Task<IActionResult> Template(string templateId)
    {
        if(!(await CallingUserId()).HasValue)return Forbid();
        var t=CallingFormCatalog.Find(templateId);if(t==null)return NotFound();
        var root=Path.Combine(_environment.ContentRootPath,"ConsentTemplates",t.FileName);
        if(!System.IO.File.Exists(root))return NotFound("Template PDF missing from this deployment.");
        return PhysicalFile(root,"application/pdf",enableRangeProcessing:true);
    }
}
