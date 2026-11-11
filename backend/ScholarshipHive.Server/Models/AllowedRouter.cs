using System.ComponentModel.DataAnnotations;

namespace ScholarshipHive.Server.Models;

public class AllowedRouter
{
    public int Id { get; set; }

    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    // MAC address of the router's wireless access point (BSSID), format AA:BB:CC:DD:EE:FF
    [Required, MaxLength(17)]
    public string Bssid { get; set; } = string.Empty;

    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
