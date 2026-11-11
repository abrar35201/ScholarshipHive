using System.ComponentModel.DataAnnotations;

namespace ScholarshipHive.Server.Models;

/// A GPS geofence around an office — separate from AllowedRouter (which stays
/// the actual attendance verification), this only wakes the mobile app's
/// attendance service on arrival/departure so it doesn't need to keep running
/// nonstop in the background all day just in case someone comes back.
public class AllowedLocation
{
    public int Id { get; set; }

    [Required, MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    public double Latitude { get; set; }

    public double Longitude { get; set; }

    /// How far from the point counts as "arrived" — generous enough to
    /// absorb ordinary GPS drift (especially indoors), since this only
    /// decides whether to start/stop watching Wi-Fi, not whether to actually
    /// mark attendance.
    public double RadiusMeters { get; set; } = 150;

    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
