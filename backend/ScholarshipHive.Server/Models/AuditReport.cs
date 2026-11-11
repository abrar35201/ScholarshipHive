namespace ScholarshipHive.Server.Models;

/// An Auditor's compiled findings about everyone else's work — separate from
/// the daily per-employee Report (which Auditors don't submit at all).
/// Not tied to a single day/attendance record since an audit can cover any
/// span of time or any number of people.
public class AuditReport
{
    public int Id { get; set; }

    public int AuditorUserId { get; set; }
    public User? AuditorUser { get; set; }

    public string Title { get; set; } = string.Empty;
    public string? TextContent { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public List<AuditReportFile> Files { get; set; } = new();
}

public class AuditReportFile
{
    public int Id { get; set; }

    public int AuditReportId { get; set; }
    public AuditReport? AuditReport { get; set; }

    public string FileName { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public byte[] FileData { get; set; } = Array.Empty<byte>();

    public DateTime UploadedAt { get; set; } = DateTime.UtcNow;
}
