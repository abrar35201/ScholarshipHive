using System.ComponentModel.DataAnnotations;
namespace ScholarshipHive.Server.Models;
public class ReceptionConsent
{
  public int Id { get; set; }
  public int? VisitorRecordId { get; set; }
  [Required, MaxLength(120)] public string ClientFullName { get; set; } = "";
  [MaxLength(120)] public string FamilyName { get; set; } = "";
  [MaxLength(25)] public string Gender { get; set; } = "";
  [MaxLength(100)] public string DomicileCity { get; set; } = "";
  [MaxLength(30)] public string CnicNumber { get; set; } = "";
  [MaxLength(40)] public string PhoneNumber { get; set; } = "";
  [MaxLength(40)] public string PassportNumber { get; set; } = "";
  [MaxLength(350)] public string FullAddress { get; set; } = "";
  [MaxLength(400)] public string QualificationDetails { get; set; } = "";
  [MaxLength(150)] public string PolicyVariant { get; set; } = "50% Refundable (Standard)";
  public int TotalPackageFee { get; set; }
  [MaxLength(120)] public string CounselorName { get; set; } = "";
  [MaxLength(30)] public string Status { get; set; } = "Draft";
  public int CreatedByUserId { get; set; }
  public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
  public DateTime? SignedAt { get; set; }
}
