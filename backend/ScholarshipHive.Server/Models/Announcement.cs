using System.ComponentModel.DataAnnotations;
namespace ScholarshipHive.Server.Models;
public class Announcement
{
    public int Id { get; set; }
    [Required, MaxLength(160)] public string Title { get; set; } = "";
    [Required, MaxLength(3000)] public string Body { get; set; } = "";
    public EmployeeDepartment? Department { get; set; }
    public int AuthorId { get; set; }
    public User? Author { get; set; }
    // Keep the original creator/ownership even after an owner edits the notice.
    public int? LastEditedByUserId { get; set; }
    public User? LastEditedByUser { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public bool IsDeleted { get; set; }
}
