using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers.Api;

[ApiController]
[Route("api/admin/chat")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Admin")]
public class ChatController : ControllerBase
{
    private readonly AiAssistantService _ai;

    public ChatController(AiAssistantService ai)
    {
        _ai = ai;
    }

    [HttpGet("status")]
    public IActionResult Status() => Ok(new { configured = _ai.IsConfigured });

    [HttpPost]
    public async Task<ActionResult<ChatResponse>> Ask([FromBody] ChatRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            return BadRequest(new ApiError { Message = "Ask something first." });
        }

        var reply = await _ai.AskAsync(request.Message.Trim(), request.ScopedUserId, request.History);
        return Ok(new ChatResponse { Reply = reply });
    }
}
