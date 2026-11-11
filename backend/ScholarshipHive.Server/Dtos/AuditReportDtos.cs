namespace ScholarshipHive.Server.Dtos;

public class AuditReportFileResponse
{
    public int Id { get; set; }
    public string FileName { get; set; } = string.Empty;
    public DateTime UploadedAt { get; set; }
}

public class AuditReportResponse
{
    public int Id { get; set; }
    public string AuditorUsername { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? TextContent { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<AuditReportFileResponse> Files { get; set; } = new();
}
