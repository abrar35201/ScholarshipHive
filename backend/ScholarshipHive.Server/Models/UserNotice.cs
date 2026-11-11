namespace ScholarshipHive.Server.Models;

/// Private notification targeted to one employee, separate from public announcements.
public class UserNotice
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Title { get; set; } = "";
    public string Body { get; set; } = "";
    public string ActorName { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
