using System.ComponentModel.DataAnnotations;
namespace ScholarshipHive.Server.Models;
public class ShiftChangeRequest
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public User? User { get; set; }
    public ShiftType ShiftType { get; set; }
    public TimeOnly Start { get; set; }
    public TimeOnly End { get; set; }
    [Required, MaxLength(1000)] public string Reason { get; set; } = "";
    [MaxLength(20)] public string Status { get; set; } = "Pending";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public int? ReviewedByUserId { get; set; }
    public DateTime? ReviewedAt { get; set; }
    [MaxLength(400)] public string? AdminNote { get; set; }
}
