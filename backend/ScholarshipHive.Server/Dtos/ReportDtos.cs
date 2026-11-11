namespace ScholarshipHive.Server.Dtos;

public class ReportFileResponse
{
    public int Id { get; set; }
    public string FileName { get; set; } = string.Empty;
    public DateTime UploadedAt { get; set; }
}

public class ReportResponse
{
    public int Id { get; set; }
    public DateOnly Date { get; set; }
    public int UnreadChats { get; set; }
    public int NewLeads { get; set; }
    public int QualifiedLeads { get; set; }
    public int FollowUp { get; set; }
    public int Calls { get; set; }
    public int Potential { get; set; }
    public int WalkIns { get; set; }
    public int Conversion { get; set; }
    public string? TextContent { get; set; }
    public List<ReportFileResponse> Files { get; set; } = new();
    public DateTime SubmittedAt { get; set; }
    public DateTime? LastEditedAt { get; set; }
    public DateTime CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    /// True only for today's report — the one day a report can still be changed.
    public bool IsEditable { get; set; }
}

public class SubmitReportRequest
{
    public int UnreadChats { get; set; }
    public int NewLeads { get; set; }
    public int QualifiedLeads { get; set; }
    public int FollowUp { get; set; }
    public int Calls { get; set; }
    public int Potential { get; set; }
    public int WalkIns { get; set; }
    public int Conversion { get; set; }
}
