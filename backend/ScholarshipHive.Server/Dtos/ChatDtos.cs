namespace ScholarshipHive.Server.Dtos;

public class ChatTurnDto
{
    /// "user" or "assistant".
    public string Role { get; set; } = "user";
    public string Content { get; set; } = string.Empty;
}

public class ChatRequest
{
    public string Message { get; set; } = string.Empty;
    /// If set, the assistant is told to focus on this user (e.g. asked from their detail page).
    public int? ScopedUserId { get; set; }
    /// Prior turns in this conversation, oldest first — kept client-side, sent back each time.
    public List<ChatTurnDto> History { get; set; } = new();
}

public class ChatResponse
{
    public string Reply { get; set; } = string.Empty;
}
