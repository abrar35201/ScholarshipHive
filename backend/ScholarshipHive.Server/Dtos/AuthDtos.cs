using System.ComponentModel.DataAnnotations;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Dtos;

public class CheckNetworkRequest
{
    [Required]
    public string Bssid { get; set; } = string.Empty;

    public string? Ssid { get; set; }

    // Presented by the phone on every authenticated check-in; prevents a
    // reset device's stale token from creating further attendance.
    public string? DeviceId { get; set; }

    // Last Android-observed Wi-Fi departure, retained while offline and replayed
    // ONLY after normal approved BSSID, GPS (when enabled), JWT and device checks.
    public DateTime? AwaySinceUtc { get; set; }

    /// Used only for local Chrome development. The API verifies Development
    /// mode, loopback Origin, and an Admin/Auditor role before honoring it.
    public bool DevelopmentBrowserAdmin { get; set; }
}

public class CheckNetworkResponse
{
    public bool Allowed { get; set; }
    public string Message { get; set; } = string.Empty;
    public bool GeofenceRequired { get; set; } = true;
}

public class GeofenceLocationDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double RadiusMeters { get; set; }
}

public class RegisterFcmTokenRequest
{
    [Required]
    public string Token { get; set; } = string.Empty;
}

public class GeofenceStatusRequest
{
    [Required]
    public bool Inside { get; set; }
}

public class ForgotPasswordRequest
{
    [Required]
    public string Username { get; set; } = string.Empty;

    /// The per-install ID this device already sends on every login/checkin — see
    /// device_id_service.dart. Must match the account's HomeDeviceId, or the request
    /// is rejected outright: this is the only proof of identity available once someone
    /// genuinely can't produce their password anymore.
    [Required]
    public string DeviceId { get; set; } = string.Empty;

    [Required, StrongPassword]
    public string NewPassword { get; set; } = string.Empty;
}

/// One pending "forgot password" request, as an admin sees it — never exposes the
/// requested password itself (see PendingPasswordReset.NewPasswordHash).
public class PendingPasswordResetDto
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string UserName { get; set; } = string.Empty;
    public DateTime RequestedAt { get; set; }

    /// False means this request's device didn't match the account's own
    /// HomeDeviceId — see PendingPasswordReset.DeviceRecognized. The admin should
    /// verify the person's identity some other way before approving one of these.
    public bool DeviceRecognized { get; set; } = true;
}

public class LoginRequest
{
    [Required]
    public string Username { get; set; } = string.Empty;

    [Required]
    public string Password { get; set; } = string.Empty;

    [Required]
    public string Bssid { get; set; } = string.Empty;

    public string? Ssid { get; set; }

    /// A device with no stored session yet has no prior IsInsideGeofence value at all — the
    /// office geofence only starts reporting AFTER a successful login. Without these, a
    /// first-ever login could never succeed once location became mandatory, since there'd be
    /// nothing on record to check yet. Optional: an older client or one still fetching its GPS
    /// fix simply omits these and falls back to whatever's already on record for this user.
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }

    /// Stable per-physical-device identifier (the Android ID) — optional so an older
    /// client still logs in fine, just without the device-switch handling below. See
    /// User.LastDeviceId and AuthController.Login for what this drives.
    public string? DeviceId { get; set; }
    public DateTime? AwaySinceUtc { get; set; }

    /// Used only for local Chrome development. The API verifies Development
    /// mode, loopback Origin, and an Admin/Auditor role before honoring it.
    public bool DevelopmentBrowserAdmin { get; set; }
}

public class UserDto
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;

    /// So the mobile app's own "on shift since / X of Y hours" progress card can
    /// size itself against THIS person's actual configured shift instead of
    /// assuming everyone works a fixed 8-hour day — an admin-set shift (e.g. an
    /// intern's 4-hour window) had nothing to reach the employee's own session
    /// with at all before this, so their own progress bar never reflected it.
    public TimeOnly ShiftStartTime { get; set; }
    public TimeOnly ShiftEndTime { get; set; }
}

public class LoginResponse
{
    public string Token { get; set; } = string.Empty;
    public UserDto User { get; set; } = new();
    public bool ReportSubmitted { get; set; }

    /// True only the first time the user logs in on a given calendar day
    /// (that's when attendance/check-in is actually recorded).
    public bool AttendanceMarked { get; set; }

    /// Today's attendance times, so the app can show a persistent "Checked in at 9:41 AM"
    /// status instead of just a one-time toast.
    public DateTime CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }

    /// Set only when this login just took over a device that was previously signed in
    /// as a DIFFERENT person — that other person has already been auto-checked-out (see
    /// AuthController.Login), and this is the one-time, user-visible explanation of why,
    /// shown right on the screen doing the switching rather than left for that other
    /// person to discover on their own later.
    public string? DeviceSwitchNotice { get; set; }
}

public class RemoteAdminLoginRequest
{
    [Required] public string Username { get; set; } = "";
    [Required] public string Password { get; set; } = "";
}

public class RegisterRequest
{
    [Required, MaxLength(50)]
    public string Username { get; set; } = string.Empty;

    [Required, StrongPassword]
    public string Password { get; set; } = string.Empty;

    [MaxLength(100)]
    public string FullName { get; set; } = string.Empty;

    [Required]
    public string Bssid { get; set; } = string.Empty;

    public string? Ssid { get; set; }

    public EmployeeDepartment Department { get; set; } = EmployeeDepartment.Calling;

    /// Which shift this person is signing up for — ShiftTypeDefaults.For maps
    /// this straight to a starting ShiftStartTime/EndTime; an admin can still
    /// fine-tune the exact hours later from the Shifts page.
    public ShiftType ShiftType { get; set; } = ShiftType.Day;
}

public class ChangeCredentialsRequest
{
    [Required]
    public string CurrentPassword { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? NewUsername { get; set; }

    [StrongPassword]
    public string? NewPassword { get; set; }
}

public class VerifyPasswordRequest
{
    [Required]
    public string Password { get; set; } = string.Empty;
}

public class ChangeCredentialsResponse
{
    public string Message { get; set; } = string.Empty;
    public UserDto User { get; set; } = new();
}

public class ApiError
{
    public string Message { get; set; } = string.Empty;

    /// Optional machine-readable reason, so the client can tell apart error cases that
    /// need a different screen/icon (e.g. "your location isn't confirmed" vs. "you're on
    /// the wrong Wi-Fi") without fragile string-matching on Message, which is meant for
    /// display and can change wording freely.
    public string? Code { get; set; }
}
