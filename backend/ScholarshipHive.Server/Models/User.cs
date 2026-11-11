using System.ComponentModel.DataAnnotations;

namespace ScholarshipHive.Server.Models;

/// Auditor has the same broad access as Admin (all users' data, all departments) — the
/// distinction is purely who they are, not what they can do: Auditor is a reviewer who
/// also submits their own audit findings, while Admin is who manages the system itself.
/// Anywhere Admin is authorized, Auditor is authorized too.
public enum UserRole
{
    Employee = 0,
    Admin = 1,
    Auditor = 2,
    Receptionist = 3,
    SuperAdmin = 4,
    Owner = 5,
    CountryHead = 6,
    HeadOfMarketing = 7,
    HeadOfProcessing = 8,
    HeadOfCounselors = 9
}

/// Which team an Employee belongs to — each has its own daily report form/fields.
/// Only meaningful for Employees; ignored for Admins/Auditors.
public enum EmployeeDepartment
{
    Calling = 0,
    Processing = 1,
    Others = 2,
    Interns = 3,
    Marketing = 4,
    // Announcement audience groups; never assign these as ordinary employee departments.
    MarketingAndInterns = 5,
    Reception = 6
}

/// Purely descriptive — which side of the clock this person normally works.
/// Doesn't drive any logic itself; ShiftStartTime is what actually decides
/// lateness. Helps an admin recognize at a glance why someone's ShiftStartTime
/// is, say, 21:00 instead of assuming a data-entry mistake.
public enum ShiftType
{
    Day = 0,
    Night = 1,
    Internship = 2
}

/// The default Start/End each ShiftType maps to — used both when a new
/// employee self-registers (they pick a shift type, not exact hours) and as
/// the starting point an admin can then fine-tune from the Shifts page.
public static class ShiftTypeDefaults
{
    public static (TimeOnly Start, TimeOnly End) For(ShiftType type) => type switch
    {
        ShiftType.Night => (new TimeOnly(18, 0), new TimeOnly(2, 0)),
        ShiftType.Internship => (new TimeOnly(18, 0), new TimeOnly(22, 0)),
        _ => (new TimeOnly(9, 30), new TimeOnly(17, 30)),
    };
}

public class User
{
    public int Id { get; set; }

    [Required, MaxLength(50)]
    public string Username { get; set; } = string.Empty;

    [Required]
    public string PasswordHash { get; set; } = string.Empty;

    [MaxLength(100)]
    public string FullName { get; set; } = string.Empty;

    public UserRole Role { get; set; } = UserRole.Employee;
    public EmployeeDepartment Department { get; set; } = EmployeeDepartment.Calling;

    /// Drives lateness: a check-in after ShiftStartTime + AttendanceRules.LateGraceMinutes
    /// is "late", anything at or before that is "on time" — see AttendanceRules.IsLate.
    /// Defaults cover every existing employee (previously a single fixed 9:15 AM cutoff for
    /// everyone) until an admin sets something else, individually or in bulk by department.
    public TimeOnly ShiftStartTime { get; set; } = new(9, 30);
    public TimeOnly ShiftEndTime { get; set; } = new(17, 30);
    public ShiftType ShiftType { get; set; } = ShiftType.Day;

    public bool IsActive { get; set; } = true;

    /// False for self-registered accounts until an admin approves them.
    /// Accounts created directly by an admin are approved immediately.
    public bool IsApproved { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public int FailedLoginAttempts { get; set; } = 0;
    public DateTime? LockedUntil { get; set; }

    /// The device's current Firebase Cloud Messaging registration token, refreshed on every
    /// login/app-open. Lets the server nudge this specific phone to run a network check via a
    /// silent push — a wake path that (unlike our own foreground-service timer) rides on Google
    /// Play Services' own Doze-exempt delivery channel, so it isn't at the mercy of aggressive
    /// OEM battery managers the way our regular alarms/timers are.
    [MaxLength(300)]
    public string? FcmToken { get; set; }

    /// Mandatory gate alongside the router check: Login/Checkin now require this to be
    /// explicitly true. Being on an approved router alone isn't proof of physical presence
    /// (a router's Wi-Fi range can reach well past the building itself) — null (location
    /// permission never granted, or the geofence hasn't reported in yet) blocks check-in
    /// too, by deliberate choice, since the mobile app's permission onboarding requires
    /// granting "Allow all the time" location before it ever attempts a check-in. Set by
    /// the on-device office geofence's enter/exit events and its own fresh-GPS-read on
    /// every (re)start — not something the app polls for on every check-in.
    public bool? IsInsideGeofence { get; set; }

    /// The physical device (Android ID, stable across app reinstalls on the same device)
    /// that most recently logged in as this user — not tracked on Checkin, only Login,
    /// since Checkin only ever resumes whatever identity is already stored on a device
    /// rather than establishing a new one. Exists so Login can tell "this phone was
    /// someone else's a moment ago" apart from "this phone has always been mine": logging
    /// in as a different person on a shared/borrowed phone silently hands that phone's
    /// background geofence tracking to the new account with nothing to stop the PREVIOUS
    /// account's attendance from being tracked by wherever that phone physically goes next
    /// — see AuthController.Login's device-switch handling for how this closes that gap.
    [MaxLength(200)]
    public string? LastDeviceId { get; set; }
    public DateTime? LastDeviceLoginAt { get; set; }

    /// Set ONCE — the first device this account ever logged in from — and never
    /// overwritten after that, unlike LastDeviceId which tracks whatever's most
    /// recent. This is what tells "signing in on my own phone" apart from
    /// "borrowing someone else's for the day": Checkin uses a mismatch between the
    /// two (see AuthController.Checkin) to end a borrowed session automatically
    /// once its calendar day is over, rather than letting it keep working
    /// indefinitely just because nobody remembered to log out.
    [MaxLength(200)]
    public string? HomeDeviceId { get; set; }

    public ICollection<Attendance> Attendances { get; set; } = new List<Attendance>();
}
