using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnlyStrict")]
public class ChatController : Controller
{
    private readonly AiAssistantService _ai;

    public ChatController(AiAssistantService ai)
    {
        _ai = ai;
    }

    public IActionResult Index()
    {
        ViewBag.Configured = _ai.IsConfigured;
        return View();
    }

    // Deliberately bound from a FORM post (with the antiforgery token as a
    // regular form field) rather than a JSON body with the token in a
    // header — Railway's edge proxy silently 400s any request whose
    // *header* value looks like a protected ASP.NET Core token (the
    // "CfDJ..." prefix), even though the identical value sails through fine
    // inside the request body. Confirmed directly: the same token in
    // X-CSRF-TOKEN gets blocked at the edge (never reaches the app), but in
    // a form field it reaches Kestrel normally.
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<ActionResult<ChatResponse>> Ask([FromForm] string message, [FromForm] string? historyJson, [FromForm] int? scopedUserId)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return BadRequest(new ApiError { Message = "Ask something first." });
        }

        var history = string.IsNullOrWhiteSpace(historyJson)
            ? new List<ChatTurnDto>()
            : JsonSerializer.Deserialize<List<ChatTurnDto>>(historyJson) ?? new List<ChatTurnDto>();

        var reply = await _ai.AskAsync(message.Trim(), scopedUserId, history);
        return Ok(new ChatResponse { Reply = reply });
    }
}
