namespace ScholarshipHive.Server.Models;

public enum ReportReviewStatus
{
    New = 0,
    SignedOff = 1,
    Flagged = 2,
    NeedsMoreDetail = 3,
}

/// One row per user per day (tied 1:1 to that day's Attendance) — editable only
/// on the day it's for; the day after, it becomes read-only history.
public class Report
{
    public int Id { get; set; }

    public int UserId { get; set; }
    public User? User { get; set; }

    public int AttendanceId { get; set; }
    public Attendance? Attendance { get; set; }

    /// Admin review workflow — set from the Reports split view (Sign off /
    /// Flag / Ask for more detail). Purely an admin-side annotation; the
    /// employee's own report content is never altered by it.
    public ReportReviewStatus ReviewStatus { get; set; } = ReportReviewStatus.New;

    public int UnreadChats { get; set; }
    public int NewLeads { get; set; }
    public int QualifiedLeads { get; set; }
    public int FollowUp { get; set; }
    public int Calls { get; set; }
    public int Potential { get; set; }
    public int WalkIns { get; set; }
    public int Conversion { get; set; }

    /// Free-form report text — used by Processing/Others departments instead
    /// of the numeric KPI fields above, which only make sense for Calling.
    public string? TextContent { get; set; }

    public DateTime SubmittedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastEditedAt { get; set; }

    /// A day's report can have any number of attached files, all accumulated
    /// under this one row rather than one row per file.
    public List<ReportFile> Files { get; set; } = new();
}

public class ReportFile
{
    public int Id { get; set; }

    public int ReportId { get; set; }
    public Report? Report { get; set; }

    public string FileName { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public byte[] FileData { get; set; } = Array.Empty<byte>();

    public DateTime UploadedAt { get; set; } = DateTime.UtcNow;
}
