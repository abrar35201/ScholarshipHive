using System.ComponentModel.DataAnnotations;
namespace ScholarshipHive.Server.Models;
public class LeaveRequest
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public User? User { get; set; }
    [MaxLength(24)] public string LeaveType { get; set; } = "Full-Day Leave";
    public DateOnly LeaveDate { get; set; }
    [Required, MaxLength(1500)] public string Reason { get; set; } = "";
    [MaxLength(16)] public string Status { get; set; } = "Pending";
    public DateTime AppliedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ReviewedAt { get; set; }
    public int? ReviewedByUserId { get; set; }
    [MaxLength(500)] public string? AdminNote { get; set; }
}
