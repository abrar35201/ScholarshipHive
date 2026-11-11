using System.ComponentModel.DataAnnotations;
namespace ScholarshipHive.Server.Models;

/// Immutable security activity summary. Never stores passwords, tokens, or field values.
public sealed class AuditEvent
{
    public long Id { get; set; }
    public string Actor { get; set; } = "System";
    public string EntityType { get; set; } = "";
    public string Action { get; set; } = "";
    public string EntityKey { get; set; } = "";
    // Only changed field names or audience, never passwords, tokens or message bodies.
    [MaxLength(500)] public string? Details { get; set; }
    public DateTime AtUtc { get; set; } = DateTime.UtcNow;
}
