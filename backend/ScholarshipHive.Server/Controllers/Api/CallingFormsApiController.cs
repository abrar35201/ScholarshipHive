using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;
namespace ScholarshipHive.Server.Controllers.Api;

public class CallingFormInput
{
    public string TemplateId { get; set; } = "";
    public string ApplicantName { get; set; } = "";
    public string Phone { get; set; } = "";
    public string? Email { get; set; }
    public Dictionary<string,string?> Answers { get; set; } = new();
}

[ApiController,Route("api/calling-forms")]
[Authorize(AuthenticationSchemes=JwtBearerDefaults.AuthenticationScheme,Roles="Employee")]
public class CallingFormsApiController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IWebHostEnvironment _env;
    public CallingFormsApiController(AppDbContext db, IWebHostEnvironment env){_db=db;_env=env;}
    private async Task<int?> CallingUserId()
    {
        if(!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),out var id))return null;
        return await _db.Users.AsNoTracking().AnyAsync(u=>u.Id==id&&u.Role==UserRole.Employee&&
          u.Department==EmployeeDepartment.Calling&&u.IsActive&&u.IsApproved) ? id : null;
    }
    [HttpGet("templates")]
    public async Task<IActionResult> Templates()
    {
        if(!(await CallingUserId()).HasValue)return Forbid();
        return Ok(CallingFormCatalog.All.Select(t=>new {id=t.Id,name=t.Name,country=t.Country,
            pdfUrl=$"/api/calling-forms/templates/{t.Id}/pdf"}));
    }
    [HttpGet("templates/{templateId}/pdf")]
    public async Task<IActionResult> Pdf(string templateId)
    {
        if(!(await CallingUserId()).HasValue)return Forbid();
        var t=CallingFormCatalog.Find(templateId);if(t==null)return NotFound();
        var path=Path.Combine(_env.ContentRootPath,"ConsentTemplates",t.FileName);
        if(!System.IO.File.Exists(path))return NotFound();
        return PhysicalFile(path,"application/pdf",enableRangeProcessing:true);
    }
    [HttpGet("submissions")]
    public async Task<IActionResult> Submissions()
    {
        var id=await CallingUserId();if(!id.HasValue)return Forbid();
        var entries=await _db.CallingFormEntries.AsNoTracking().Where(x=>x.CreatedByUserId==id.Value)
           .OrderByDescending(x=>x.CreatedAt).Take(100).ToListAsync();
        return Ok(entries.Select(x=>new {x.Id,x.TemplateId,x.ApplicantName,x.Phone,x.Email,x.CreatedAt}));
    }
    [HttpGet("submissions/{id:int}")]
    public async Task<IActionResult> Detail(int id)
    {
        var user=await CallingUserId();if(!user.HasValue)return Forbid();
        var e=await _db.CallingFormEntries.AsNoTracking().FirstOrDefaultAsync(x=>x.Id==id&&x.CreatedByUserId==user.Value);
        if(e==null)return NotFound();
        return Ok(new {e.Id,e.TemplateId,e.ApplicantName,e.Phone,e.Email,e.CreatedAt,
            Answers=JsonSerializer.Deserialize<Dictionary<string,string>>(e.AnswersJson)});
    }
    [HttpPost("submissions")]
    public async Task<IActionResult> Submit([FromBody]CallingFormInput form)
    {
        var user=await CallingUserId();if(!user.HasValue)return Forbid();
        if(CallingFormCatalog.Find(form.TemplateId)==null)return BadRequest(new {message="Unknown template."});
        var name=(form.ApplicantName??"").Trim();var phone=(form.Phone??"").Trim();var email=form.Email?.Trim();
        if(name.Length is <2 or >120||phone.Length is <7 or >40||email?.Length>150||form.Answers==null||form.Answers.Count>50)
            return BadRequest(new {message="Invalid applicant details."});
        var answers=new Dictionary<string,string>();
        foreach(var (key,value) in form.Answers)
        {
            if(!CallingFormCatalog.ValidField(key)||(value?.Length??0)>350)
                return BadRequest(new {message="Invalid field."});
            if(!string.IsNullOrWhiteSpace(value))answers[key]=value.Trim();
        }
        var json=JsonSerializer.Serialize(answers);
        if(json.Length>14000)return BadRequest(new {message="Form too large."});
        var entry=new CallingFormEntry{CreatedByUserId=user.Value,TemplateId=form.TemplateId,ApplicantName=name,
            Phone=phone,Email=email,AnswersJson=json,CreatedAt=DateTime.UtcNow};
        _db.CallingFormEntries.Add(entry);await _db.SaveChangesAsync();
        return Ok(new{id=entry.Id,message="Application draft saved. Signed consent must be completed separately."});
    }
}
