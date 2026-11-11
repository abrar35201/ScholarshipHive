using System.ComponentModel.DataAnnotations;
namespace ScholarshipHive.Server.Models;
public class VisitorRecord
{
    public int Id { get; set; }
    [Required,MaxLength(120)] public string FullName { get; set; } = "";
    [MaxLength(40)] public string? Contact { get; set; }
    [MaxLength(150)] public string? Email { get; set; }
    [MaxLength(100)] public string? Qualification { get; set; }
    [MaxLength(100)] public string? Country { get; set; }
    [MaxLength(100)] public string? Program { get; set; }
    [MaxLength(40)] public string? InquiryType { get; set; }
    [MaxLength(100)] public string? Counsellor { get; set; }
    [MaxLength(1000)] public string? Remarks { get; set; }
    public int RegisteredByUserId { get; set; }
    public DateTime CheckInTime { get; set; } = DateTime.UtcNow;
    public DateTime? CheckOutTime { get; set; }
}
