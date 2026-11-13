using System.ComponentModel.DataAnnotations;
namespace ScholarshipHive.Server.Models;

// Application details captured for one original country-specific PDF template.
// This is a draft, not a digitally signed or legally executed consent agreement.
public class CallingFormEntry
{
    public int Id { get; set; }
    public int CreatedByUserId { get; set; }
    public User CreatedByUser { get; set; } = null!;
    [Required, MaxLength(80)] public string TemplateId { get; set; } = "";
    [Required, MaxLength(120)] public string ApplicantName { get; set; } = "";
    [Required, MaxLength(40)] public string Phone { get; set; } = "";
    [MaxLength(150)] public string? Email { get; set; }
    // Remaining template application fields (never user-supplied field names).
    [Required, MaxLength(14000)] public string AnswersJson { get; set; } = "{}";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    // SHA256 of a random 256-bit bearer token, not the raw public link.
    [MaxLength(64)] public string? PublicShareTokenHash { get; set; }
    public DateTime? PublicShareCreatedAt { get; set; }

}
