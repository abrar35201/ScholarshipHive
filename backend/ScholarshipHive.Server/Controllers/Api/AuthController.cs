using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers.Api;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly IDataProtector _biometricProtector;
    private sealed record BiometricTicket(int UserId, string Username, string DeviceId, string PasswordFingerprint, long ExpiresUtcTicks);
    public sealed record BiometricEnrollRequest(string DeviceId);
    public sealed record BiometricLoginRequest(string Username, string DeviceId, string Credential, string? Bssid, string? Ssid);

    private static string PasswordFingerprint(string passwordHash) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(passwordHash)));

    private readonly AppDbContext _db;
    private readonly NetworkAccessService _networkAccess;
    private readonly IPasswordHasher<User> _hasher;
    private readonly JwtTokenService _jwt;
    private readonly RealtimeNotifier _realtime;
    private readonly FcmPushService _fcmPush;
    private readonly IWebHostEnvironment _environment;
    private readonly bool _geofenceRequired;

    public AuthController(AppDbContext db, NetworkAccessService networkAccess, IPasswordHasher<User> hasher, JwtTokenService jwt, RealtimeNotifier realtime, FcmPushService fcmPush, IWebHostEnvironment environment, IConfiguration configuration, IDataProtectionProvider dataProtectionProvider)
    {
        _biometricProtector = dataProtectionProvider.CreateProtector("ScholarshipHive.BiometricTicket.v1");
        _db = db;
        _networkAccess = networkAccess;
        _hasher = hasher;
        _jwt = jwt;
        _realtime = realtime;
        _fcmPush = fcmPush;
        _environment = environment;
        // Production always requires a geofence. The Development override makes
        // local Wi-Fi/BSSID verification usable while leaving geofence data and
        // code in place for an easy re-enable.
        _geofenceRequired = !environment.IsDevelopment() || configuration.GetValue("Attendance:RequireGeofence", true);
    }

    [HttpPost("check-network")]
    [AllowAnonymous]
    public async Task<ActionResult<CheckNetworkResponse>> CheckNetwork([FromBody] CheckNetworkRequest request)
    {
        // No coordinates come with this call at all (it runs before any location fix
        // exists), so `insideGeofence` stays null here on purpose — an unrecognized
        // network hit from this endpoint never gets logged as pending.
        var result = await _networkAccess.CheckAsync(request.Bssid, ClientIpResolver.Resolve(HttpContext), request.Ssid);
        return Ok(new CheckNetworkResponse
        {
            Allowed = result.Allowed,
            Message = result.Message,
            GeofenceRequired = _geofenceRequired
        });
    }

    /// A "forgot password" request — not a self-service reset. It only ever queues a
    /// PendingPasswordReset for an admin to approve; the account's actual password
    /// never changes here. Matching the account's own HomeDeviceId (the same
    /// per-install ID already sent on every login/checkin, see device_id_service.dart
    /// on mobile) is the strongest signal available, but it is NOT required to reach an
    /// admin at all: a genuine reinstall, a cleared app storage, or a new phone means
    /// that match is simply unavailable to the one person who needs this flow most —
    /// refusing outright in that case left them permanently stuck (HomeDeviceId only
    /// ever re-anchors via a successful password Login, which is exactly what they
    /// can't do). The request always goes through either way now; DeviceRecognized is
    /// what tells the admin whether to trust it on sight or verify the person's
    /// identity some other way (call them, ask in person) before approving it.
    [HttpPost("forgot-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
    {
        var normalizedUsername = request.Username.Trim().ToLowerInvariant();
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == normalizedUsername);

        // Only a genuinely nonexistent username is rejected outright — telling that
        // apart from "device unrecognized" would let someone probe for valid
        // usernames simply by watching which error comes back, and unlike the device
        // check, there is no account here at all for an admin to ever review.
        if (user is null)
        {
            return StatusCode(403, new ApiError { Message = "This can only be requested from your account's original device." });
        }

        var deviceRecognized = !string.IsNullOrWhiteSpace(user.HomeDeviceId) && user.HomeDeviceId == request.DeviceId;

        var existing = await _db.PendingPasswordResets.FirstOrDefaultAsync(p => p.UserId == user.Id);
        var hash = _hasher.HashPassword(user, request.NewPassword);
        if (existing is not null)
        {
            existing.NewPasswordHash = hash;
            existing.DeviceId = request.DeviceId;
            existing.RequestedAt = DateTime.UtcNow;
            existing.DeviceRecognized = deviceRecognized;
        }
        else
        {
            _db.PendingPasswordResets.Add(new PendingPasswordReset
            {
                UserId = user.Id,
                NewPasswordHash = hash,
                DeviceId = request.DeviceId,
                RequestedAt = DateTime.UtcNow,
                DeviceRecognized = deviceRecognized
            });
        }
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("password-resets");

        return Ok(new { message = "Request sent — an admin will review it shortly." });
    }

    // Receptionists can request an account without being inside the office.
    // Their account remains disabled for login until an Admin approves it.
    [HttpPost("register-reception")]
    [AllowAnonymous]
    public async Task<IActionResult> RegisterReception([FromBody] RegisterRequest request)
    {
        var normalized = request.Username.Trim().ToLowerInvariant();
        if (await _db.Users.AnyAsync(u => u.Username.ToLower() == normalized))
            return BadRequest(new ApiError { Message = "This username is already taken." });
        var user = new User
        {
            Username = request.Username.Trim(), FullName = request.FullName.Trim(),
            Role = UserRole.Receptionist, Department = EmployeeDepartment.Others,
            IsActive = true, IsApproved = false
        };
        user.PasswordHash = _hasher.HashPassword(user, request.Password);
        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("users");
        var adminTokens = await _db.Users.Where(u => u.IsActive && u.IsApproved && u.Role == UserRole.Admin && u.FcmToken != null)
            .Select(u => u.FcmToken!).ToListAsync();
        foreach (var token in adminTokens)
            await _fcmPush.SendNotificationAsync(token, "Reception account pending", $"New receptionist {user.Username} needs your approval.");
        return Ok(new { message = "Reception registration submitted for admin approval." });
    }

    // Strictly admin-only remote login: no router bypass for employees/reception,
    // and never creates attendance when logging in remotely.
    [HttpPost("remote-admin-login")]
    [AllowAnonymous]
    public async Task<ActionResult<LoginResponse>> RemoteAdminLogin([FromBody] RemoteAdminLoginRequest request)
    {
        var normalized = request.Username.Trim().ToLowerInvariant();
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == normalized && u.IsActive);
        if (user == null || !user.IsApproved)
            return Unauthorized(new ApiError { Message = "Invalid username or password." });
        if (user.LockedUntil > DateTime.UtcNow)
            return StatusCode(423, new ApiError { Message = "Account temporarily locked." });
        var verified = _hasher.VerifyHashedPassword(user, user.PasswordHash, request.Password);
        if (verified == PasswordVerificationResult.Failed)
        {
            user.FailedLoginAttempts++;
            if (user.FailedLoginAttempts >= AuthPolicy.MaxFailedAttempts)
            {
                user.LockedUntil = DateTime.UtcNow.Add(AuthPolicy.LockoutDuration);
                user.FailedLoginAttempts = 0;
            }
            await _db.SaveChangesAsync();
            return Unauthorized(new ApiError { Message = "Invalid username or password." });
        }
        // A valid employee/reception credential must go through the ordinary
        // Wi-Fi/attendance flow. Only an administrator-appointed management role
        // can use this Wi-Fi-independent login path.
        if (!AccessRules.IsPrimaryAdmin(user))
            return Conflict(new ApiError { Message = "Office network verification required.", Code = "office_network_required" });
        user.FailedLoginAttempts = 0;
        user.LockedUntil = null;
        await _db.SaveChangesAsync();
        return Ok(CreateDevelopmentBrowserAdminResponse(user));
    }

    // Enrollment requires an already password-authenticated JWT. No password or
    // permanent JWT is stored in the mobile biometric profile.
    [HttpPost("biometric-enroll")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> BiometricEnroll([FromBody] BiometricEnrollRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DeviceId))
            return BadRequest(new ApiError { Message = "A registered device is required." });
        var user = await _db.Users.FindAsync(GetUserId());
        if (user is null || !user.IsActive || !user.IsApproved)
            return Unauthorized(new ApiError { Message = "Account not approved or active." });
        if (AccessRules.RequiresAttendance(user) && user.HomeDeviceId != request.DeviceId)
            return StatusCode(403, new ApiError { Message = "This device is not registered to your account." });
        var ticket = new BiometricTicket(user.Id, user.Username, request.DeviceId,
            PasswordFingerprint(user.PasswordHash), DateTime.UtcNow.AddDays(365).Ticks);
        return Ok(new { credential = _biometricProtector.Protect(JsonSerializer.Serialize(ticket)) });
    }

    // Fingerprint only unlocks the device-local credential. The server then
    // independently verifies its username, install ID, password version and
    // account approval. An Admin credential can NEVER log in as an Employee.
    [HttpPost("biometric-login")]
    [AllowAnonymous]
    public async Task<ActionResult<LoginResponse>> BiometricLogin([FromBody] BiometricLoginRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Username) ||
            string.IsNullOrWhiteSpace(request.DeviceId) || string.IsNullOrWhiteSpace(request.Credential))
            return Unauthorized(new ApiError { Message = "Fingerprint login is not enabled for this account." });
        BiometricTicket ticket;
        try
        {
            ticket = JsonSerializer.Deserialize<BiometricTicket>(_biometricProtector.Unprotect(request.Credential))!;
        }
        catch (Exception)
        {
            return Unauthorized(new ApiError { Message = "Fingerprint enrollment expired or invalid. Sign in with your password." });
        }
        var username = request.Username.Trim();
        if (ticket.ExpiresUtcTicks <= DateTime.UtcNow.Ticks ||
            !string.Equals(ticket.Username, username, StringComparison.OrdinalIgnoreCase) ||
            ticket.DeviceId != request.DeviceId)
            return Unauthorized(new ApiError { Message = "Fingerprint belongs to a different account/device or has expired." });
        var user = await _db.Users.FindAsync(ticket.UserId);
        if (user is null || !user.IsActive || !user.IsApproved ||
            !string.Equals(user.Username, username, StringComparison.OrdinalIgnoreCase) ||
            !CryptographicOperations.FixedTimeEquals(
                Encoding.ASCII.GetBytes(PasswordFingerprint(user.PasswordHash)),
                Encoding.ASCII.GetBytes(ticket.PasswordFingerprint)))
            return Unauthorized(new ApiError { Message = "Account changed. Sign in with your password and re-enable fingerprint." });
        if (user.LockedUntil > DateTime.UtcNow)
            return StatusCode(423, new ApiError { Message = "Account temporarily locked." });

        // Only employees create attendance, and ONLY on approved office Wi-Fi.
        // Privileged accounts do not create attendance or require an office BSSID.
        if (!AccessRules.RequiresAttendance(user))
            return Ok(CreateDevelopmentBrowserAdminResponse(user));

        if (string.IsNullOrWhiteSpace(request.Bssid))
            return StatusCode(403, new ApiError { Message = "Connect to approved office Wi-Fi to sign in for attendance." });
        var network = await _networkAccess.CheckAsync(request.Bssid,
            ClientIpResolver.Resolve(HttpContext), request.Ssid,
            _geofenceRequired ? user.IsInsideGeofence : null);
        if (!network.Allowed)
            return StatusCode(403, new ApiError { Message = network.Message });
        if (_geofenceRequired && user.IsInsideGeofence != true)
            return StatusCode(403, new ApiError { Message = "Office location isn't confirmed yet." });
        if (string.IsNullOrWhiteSpace(user.HomeDeviceId) || user.HomeDeviceId != request.DeviceId)
            return StatusCode(403, new ApiError { Message = "Fingerprint attendance is restricted to the original device. Use password login." });

        // Close another account's still-open attendance when this shared device
        // switches users, just like password login does.
        var previous = await _db.Users.FirstOrDefaultAsync(u => u.Id != user.Id && u.LastDeviceId == request.DeviceId);
        if (previous is not null)
        {
            var open = await _db.Attendances.FirstOrDefaultAsync(a => a.UserId == previous.Id &&
                a.Date == DateTimeExtensions.PakistanToday() && a.CheckOutTime == null);
            if (open is not null)
            {
                open.CheckOutTime = DateTime.UtcNow;
                LogHistory(previous.Id, LoginHistoryEvent.CheckOut, open.DeviceBssid);
            }
        }
        user.LastDeviceId = request.DeviceId;
        user.LastDeviceLoginAt = DateTime.UtcNow;
        var (attendance, marked, reopened) = await EnsureTodayAttendanceAsync(user, request.Bssid);
        if (marked || reopened) LogHistory(user.Id, LoginHistoryEvent.CheckIn, request.Bssid);
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("attendance");
        return Ok(new LoginResponse
        {
            Token = _jwt.GenerateToken(user), User = ToDto(user),
            ReportSubmitted = attendance.ReportSubmitted, AttendanceMarked = marked,
            CheckInTime = attendance.CheckInTime, CheckOutTime = attendance.CheckOutTime
        });
    }

    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        // Same as CheckNetwork above — no coordinates at registration time, so this
        // never logs an unrecognized network as pending either.
        var network = await _networkAccess.CheckAsync(request.Bssid, ClientIpResolver.Resolve(HttpContext), request.Ssid);
        if (!network.Allowed)
        {
            return StatusCode(403, new ApiError { Message = network.Message });
        }

        if (!AccessRules.IsActualEmployeeDepartment(request.Department))
            return BadRequest(new ApiError { Message = "Choose a valid employee department." });
        var normalizedUsername = request.Username.Trim().ToLowerInvariant();
        if (await _db.Users.AnyAsync(u => u.Username.ToLower() == normalizedUsername))
        {
            return BadRequest(new ApiError { Message = "This username is already taken." });
        }

        var (shiftStart, shiftEnd) = ShiftTypeDefaults.For(request.ShiftType);
        var user = new User
        {
            Username = request.Username.Trim(),
            FullName = request.FullName.Trim(),
            Role = UserRole.Employee,
            Department = request.Department,
            ShiftType = request.ShiftType,
            ShiftStartTime = shiftStart,
            ShiftEndTime = shiftEnd,
            IsActive = true,
            IsApproved = false
        };
        user.PasswordHash = _hasher.HashPassword(user, request.Password);

        _db.Users.Add(user);
        await _db.SaveChangesAsync();

        return Ok(new { message = "Registration submitted. An admin needs to approve your account before you can log in." });
    }

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<ActionResult<LoginResponse>> Login([FromBody] LoginRequest request)
    {
        // Computed from the request's own coordinates, ahead of the network check below,
        // so an unrecognized router only gets logged as pending when this device was
        // actually confirmed inside an approved geofence at the time — not for every
        // random Wi-Fi a first-time login happens to be on. Reused again further down
        // instead of recomputed, once `user` exists, to actually set IsInsideGeofence.
        bool? insideGeofenceNow = null;
        if (_geofenceRequired && request.Latitude is not null && request.Longitude is not null)
        {
            var candidateLocations = await _db.AllowedLocations.Where(l => l.IsActive).ToListAsync();
            insideGeofenceNow = candidateLocations.Any(l =>
                DistanceMeters(request.Latitude.Value, request.Longitude.Value, l.Latitude, l.Longitude) <= l.RadiusMeters);
        }

        var normalizedUsername = request.Username.Trim().ToLowerInvariant();
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == normalizedUsername && u.IsActive);
        var developmentBrowserAdmin = user is not null && AccessRules.IsPrimaryAdmin(user) && IsDevelopmentBrowserAdminRequest(request.DevelopmentBrowserAdmin, user.Role);

        if (!developmentBrowserAdmin && (user == null || AccessRules.RequiresAttendance(user)))
        {
            var network = await _networkAccess.CheckAsync(request.Bssid, ClientIpResolver.Resolve(HttpContext), request.Ssid,
                _geofenceRequired ? insideGeofenceNow : null);
            if (!network.Allowed)
            {
                return StatusCode(403, new ApiError { Message = network.Message });
            }
        }

        if (user is null)
        {
            return Unauthorized(new ApiError { Message = "Invalid username or password." });
        }

        if (user.LockedUntil is not null && user.LockedUntil > DateTime.UtcNow)
        {
            var minutesLeft = Math.Ceiling((user.LockedUntil.Value - DateTime.UtcNow).TotalMinutes);
            return StatusCode(423, new ApiError
            {
                Message = $"Too many failed attempts. Try again in {minutesLeft} minute(s)."
            });
        }

        var verify = _hasher.VerifyHashedPassword(user, user.PasswordHash, request.Password);
        if (verify == PasswordVerificationResult.Failed)
        {
            user.FailedLoginAttempts++;
            if (user.FailedLoginAttempts >= AuthPolicy.MaxFailedAttempts)
            {
                user.LockedUntil = DateTime.UtcNow.Add(AuthPolicy.LockoutDuration);
                user.FailedLoginAttempts = 0;
            }
            await _db.SaveChangesAsync();
            return Unauthorized(new ApiError { Message = "Invalid username or password." });
        }

        if (!user.IsApproved)
        {
            return StatusCode(403, new ApiError { Message = "Your registration is still pending admin approval." });
        }

        user.FailedLoginAttempts = 0;
        user.LockedUntil = null;

        if (developmentBrowserAdmin || AccessRules.IsPrimaryAdmin(user))
        {
            // Admin/reception accounts never create employee attendance; admin remote
            // login is handled by its own credential-verified endpoint.
            // Local web admin access is for managing and inspecting the dev
            // app. It must not create, reopen, or close attendance records.
            await _db.SaveChangesAsync();
            return Ok(CreateDevelopmentBrowserAdminResponse(user));
        }

        // A brand new device has no prior IsInsideGeofence value at all — the on-device
        // geofence only starts reporting AFTER a successful login, so without this, a
        // first-ever login could never succeed once location became mandatory (nothing
        // would ever be on record to check). Already computed above (before the network
        // check ran) from the same request coordinates — reused here rather than querying
        // AllowedLocations a second time.
        if (insideGeofenceNow is not null)
        {
            user.IsInsideGeofence = insideGeofenceNow;
        }

        // Being on the approved router alone isn't proof of physical presence — its Wi-Fi
        // range can reach well past the building. Location is mandatory: only an explicit,
        // confirmed "inside an approved office geofence" passes here now — null (location
        // permission never granted, or the geofence hasn't reported in yet) also blocks,
        // by deliberate choice, since the mobile app's permission onboarding now requires
        // granting "Allow all the time" location before check-in is ever attempted anyway.
        if (_geofenceRequired && user.IsInsideGeofence != true)
        {
            await _db.SaveChangesAsync();
            return StatusCode(403, new ApiError
            {
                Code = "location_not_confirmed",
                Message = "Location isn't confirmed yet — make sure location access is set to \"Allow all the time\" for ScholarshipHive, then try again."
            });
        }

        // Strict employee device binding: first successful authorized office login registers the phone.
        // No automatic reassignment after one/two days. Admin must explicitly reset a lost device.
        if (string.IsNullOrWhiteSpace(request.DeviceId))
            return StatusCode(403, new ApiError { Code = "device_required", Message = "Android device identity required. Ask admin for help." });
        if (!string.IsNullOrWhiteSpace(user.HomeDeviceId) && user.HomeDeviceId != request.DeviceId)
            return StatusCode(403, new ApiError { Code = "device_bound", Message = "Account registered on another phone. Contact admin to reset registered device." });
        var occupied = await _db.Users.AnyAsync(u => u.Id != user.Id && u.IsActive &&
            !((u.Role == UserRole.Admin) && u.Username.ToLower() == "admin") && u.HomeDeviceId == request.DeviceId);
        if (occupied)
            return StatusCode(403, new ApiError { Code = "device_in_use", Message = "This phone is already registered to another employee." });
        if (string.IsNullOrWhiteSpace(user.HomeDeviceId)) user.HomeDeviceId = request.DeviceId;
        user.LastDeviceId = request.DeviceId;
        user.LastDeviceLoginAt = DateTime.UtcNow;
        string? deviceSwitchNotice = null;

        var (attendance, attendanceMarked, reopened) = await EnsureTodayAttendanceAsync(user, request.Bssid, request.AwaySinceUtc);

        // Only a genuine arrival (brand new day) or a real reopen (this device's own
        // session had actually been closed out) is worth a history entry — logging one
        // on every plain re-login would double up on top of whatever's already open,
        // e.g. typing a password to clear the fingerprint lock while already checked in
        // for the day (see BiometricLockGate) used to log a spurious extra CheckIn here
        // even though nothing about the actual attendance session changed.
        if (attendanceMarked || reopened)
        {
            LogHistory(user.Id, LoginHistoryEvent.CheckIn, request.Bssid);
        }
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("attendance");

        var token = _jwt.GenerateToken(user);

        return Ok(new LoginResponse
        {
            Token = token,
            User = ToDto(user),
            ReportSubmitted = attendance.ReportSubmitted,
            AttendanceMarked = attendanceMarked,
            CheckInTime = attendance.CheckInTime,
            CheckOutTime = attendance.CheckOutTime,
            DeviceSwitchNotice = deviceSwitchNotice
        });
    }

    /// Called every time the app opens (network + a previously stored token are enough).
    /// No password is asked again — this is what lets a user check in for the day just by
    /// being on the approved network, without logging in every single time.
    [HttpPost("checkin")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<ActionResult<LoginResponse>> Checkin([FromBody] CheckNetworkRequest request)
    {
        var userId = GetUserId();
        var user = await _db.Users.FindAsync(userId);
        if (user is null || !user.IsActive || !user.IsApproved)
        {
            return Unauthorized(new ApiError { Message = "Your account is no longer active. Please log in again." });
        }

        // Device reset cuts off even an old employee JWT before it can make new attendance.
        if (AccessRules.RequiresAttendance(user) &&
            (string.IsNullOrWhiteSpace(user.HomeDeviceId) || user.HomeDeviceId != request.DeviceId))
            return StatusCode(403, new ApiError { Code = "device_revoked", Message = "This phone is no longer registered to this account. Contact admin." });

        if (AccessRules.IsPrimaryAdmin(user))
        {
            // Refresh an administrative/reception session without touching attendance
            // or requiring native BSSID/geofence APIs.
            return Ok(CreateDevelopmentBrowserAdminResponse(user));
        }

        // user.IsInsideGeofence is whatever this device's last confirmed GPS report said —
        // an unrecognized network only gets logged as pending when that's actually true,
        // not for every random Wi-Fi this phone happens to be near.
        var network = await _networkAccess.CheckAsync(request.Bssid, ClientIpResolver.Resolve(HttpContext), request.Ssid,
            _geofenceRequired ? user.IsInsideGeofence : null);
        if (!network.Allowed)
        {
            return StatusCode(403, new ApiError { Message = network.Message });
        }

        // The phone is permanently linked during password login; the backend token is
        // used only to continue that employee's authorized attendance session.
        // See the matching check in Login — location is mandatory, so null (never confirmed) blocks too.
        if (_geofenceRequired && user.IsInsideGeofence != true)
        {
            return StatusCode(403, new ApiError
            {
                Code = "location_not_confirmed",
                Message = "Location isn't confirmed yet — make sure location access is set to \"Allow all the time\" for ScholarshipHive."
            });
        }

        var (attendance, attendanceMarked, reopened) = await EnsureTodayAttendanceAsync(user, request.Bssid, request.AwaySinceUtc);
        // The mobile app calls this endpoint on a repeating background timer while it
        // stays on the approved network, not just once — only log a history entry on an
        // actual arrival (brand new day, or coming back after having left), not on every
        // routine heartbeat tick while the employee never left in the first place.
        if (attendanceMarked || reopened)
        {
            LogHistory(user.Id, LoginHistoryEvent.CheckIn, request.Bssid);
        }
        await _db.SaveChangesAsync();
        await _realtime.NotifyAsync("attendance");

        // Re-issue the token so a user who opens the app regularly never hits the expiry.
        var token = _jwt.GenerateToken(user);

        return Ok(new LoginResponse
        {
            Token = token,
            User = ToDto(user),
            ReportSubmitted = attendance.ReportSubmitted,
            AttendanceMarked = attendanceMarked,
            CheckInTime = attendance.CheckInTime,
            CheckOutTime = attendance.CheckOutTime
        });
    }

    /// The set of office geofences the app should register on-device so it can
    /// wake its own attendance service on arrival/departure instead of needing
    /// to run nonstop in the background. Deliberately not tied to the specific
    /// router the app happens to be checking against — every active office
    /// location goes to every signed-in device.
    [HttpGet("geofence-locations")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<ActionResult<List<GeofenceLocationDto>>> GeofenceLocations()
    {
        var locations = await _db.AllowedLocations.Where(l => l.IsActive).ToListAsync();
        return Ok(locations.Select(l => new GeofenceLocationDto
        {
            Id = l.Id,
            Name = l.Name,
            Latitude = l.Latitude,
            Longitude = l.Longitude,
            RadiusMeters = l.RadiusMeters
        }).ToList());
    }

    /// Called from the on-device office geofence's own enter/exit callbacks — this is the
    /// only way IsInsideGeofence ever changes. Login/Checkin both refuse to proceed while
    /// this is explicitly false, so an exit here also closes the door on any check-in attempt
    /// that only has the (spoofable/long-range) Wi-Fi signal going for it.
    [HttpPost("geofence-status")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> GeofenceStatus([FromBody] GeofenceStatusRequest request)
    {
        var userId = GetUserId();
        var user = await _db.Users.FindAsync(userId);
        if (user is null)
        {
            return Unauthorized(new ApiError { Message = "User not found." });
        }

        user.IsInsideGeofence = request.Inside;
        await _db.SaveChangesAsync();
        return Ok();
    }

    /// Called on every login/app-open so the server always has this device's current FCM
    /// token — tokens can rotate at any time (reinstall, Play Services data clear, etc.), so
    /// this isn't a one-time registration but a refresh-on-every-opportunity.
    [HttpPost("register-fcm-token")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> RegisterFcmToken([FromBody] RegisterFcmTokenRequest request)
    {
        var userId = GetUserId();
        var user = await _db.Users.FindAsync(userId);
        if (user is null)
        {
            return Unauthorized(new ApiError { Message = "User not found." });
        }

        user.FcmToken = request.Token;
        await _db.SaveChangesAsync();
        return Ok();
    }

    [HttpPost("change-credentials")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<ActionResult<ChangeCredentialsResponse>> ChangeCredentials([FromBody] ChangeCredentialsRequest request)
    {
        var userId = GetUserId();
        var user = await _db.Users.FindAsync(userId);
        if (user is null)
        {
            return Unauthorized(new ApiError { Message = "User not found." });
        }

        if (_hasher.VerifyHashedPassword(user, user.PasswordHash, request.CurrentPassword) == PasswordVerificationResult.Failed)
        {
            return BadRequest(new ApiError { Message = "Current password is incorrect." });
        }

        if (string.IsNullOrWhiteSpace(request.NewUsername) && string.IsNullOrWhiteSpace(request.NewPassword))
        {
            return BadRequest(new ApiError { Message = "Provide a new username and/or a new password." });
        }

        if (!string.IsNullOrWhiteSpace(request.NewUsername))
        {
            var normalized = request.NewUsername.Trim().ToLowerInvariant();
            if (await _db.Users.AnyAsync(u => u.Username.ToLower() == normalized && u.Id != user.Id))
            {
                return BadRequest(new ApiError { Message = "That username is already taken." });
            }
            user.Username = request.NewUsername.Trim();
        }

        if (!string.IsNullOrWhiteSpace(request.NewPassword))
        {
            user.PasswordHash = _hasher.HashPassword(user, request.NewPassword);
        }

        await _db.SaveChangesAsync();

        return Ok(new ChangeCredentialsResponse
        {
            Message = "Your credentials were updated successfully.",
            User = ToDto(user)
        });
    }

    /// Re-authentication checkpoint — e.g. an Admin has to re-confirm their OWN
    /// password before reaching the "set a new password for this user" screen.
    /// Passwords are one-way hashed (see StrongPasswordAttribute doc comment
    /// for the "why") so nobody, including an Admin, can ever view an existing
    /// password — re-entering your own is the closest equivalent safeguard.
    [HttpPost("verify-password")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> VerifyPassword([FromBody] VerifyPasswordRequest request)
    {
        var userId = GetUserId();
        var user = await _db.Users.FindAsync(userId);
        if (user is null)
        {
            return Unauthorized(new ApiError { Message = "User not found." });
        }

        if (_hasher.VerifyHashedPassword(user, user.PasswordHash, request.Password) == PasswordVerificationResult.Failed)
        {
            return BadRequest(new ApiError { Message = "Incorrect password." });
        }

        return Ok();
    }

    /// Logging out (or the app detecting the user left the approved network) always
    /// succeeds — submitting a report is entirely the employee's choice, never a
    /// requirement to end their shift.
    [HttpPost("logout")]
    [Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme)]
    public async Task<IActionResult> Logout()
    {
        var userId = GetUserId();
        var user = await _db.Users.FindAsync(userId);
        if (user is not null && AccessRules.IsPrimaryAdmin(user))
        {
            // An admin/reception session never opened attendance, so logging
            // it out must not check out an Android attendance session for the
            // same account.
            return Ok(new { message = "Logged out successfully." });
        }

        var today = DateTimeExtensions.PakistanToday();
        var attendance = await _db.Attendances
            .FirstOrDefaultAsync(a => a.UserId == userId && a.Date == today);

        if (attendance is null)
        {
            return BadRequest(new ApiError { Message = "No attendance found for today. Please log in again." });
        }

        // Idempotent on purpose: the mobile app's background monitor can call this twice
        // in quick succession during a real network handoff (its periodic timer and its
        // connectivity-changed listener can both fire around the same moment), and without
        // this guard each call unconditionally stamped a new CheckOut — producing two
        // check-outs in the history with no check-in between them.
        if (attendance.CheckOutTime is null)
        {
            attendance.CheckOutTime = DateTime.UtcNow;
            LogHistory(userId, LoginHistoryEvent.CheckOut, attendance.DeviceBssid);
            await _db.SaveChangesAsync();
            await _realtime.NotifyAsync("attendance");
        }

        return Ok(new { message = "Logged out successfully." });
    }

    private void LogHistory(int userId, LoginHistoryEvent eventType, string? bssid)
    {
        _db.LoginHistories.Add(new LoginHistory
        {
            UserId = userId,
            EventType = eventType,
            Timestamp = DateTime.UtcNow,
            Bssid = bssid
        });
    }

    /// Ensures today's Attendance row exists (first login/check-in of the day marks it;
    /// later ones the same day just reuse it). If the employee had already checked out
    /// today and is now checking in again (left for lunch and came back, Wi-Fi dropped
    /// and reconnected, etc.), this reopens the row by clearing CheckOutTime — otherwise
    /// the Home screen would keep showing a stale "checked out at ..." time even though
    /// they're back. `reopened` lets the caller distinguish a genuine new arrival (worth
    /// a LoginHistory entry) from a routine re-affirmation while never having left.
    /// Caller must still call SaveChangesAsync.
    private async Task<(Attendance attendance, bool attendanceMarked, bool reopened)> EnsureTodayAttendanceAsync(User user, string bssid, DateTime? awaySinceUtc = null)
    {
        var today = DateTimeExtensions.PakistanToday();
        var attendance = await _db.Attendances
            .FirstOrDefaultAsync(a => a.UserId == user.Id && a.Date == today);

        if (attendance is not null)
        {
            // Never reopen a business-day session after the 10-hour elapsed cap.
            // The user's next fresh business day may create a new attendance row.
            var deadline = attendance.CheckInTime.AddHours(10);
            if (DateTime.UtcNow >= deadline)
            {
                if (attendance.CheckOutTime == null)
                {
                    attendance.CheckOutTime = deadline;
                    _db.LoginHistories.Add(new LoginHistory { UserId = user.Id,
                        EventType = LoginHistoryEvent.CheckOut, Timestamp = deadline,
                        Bssid = attendance.DeviceBssid });
                }
                return (attendance, false, false);
            }
            // A disconnected phone may not reach the server at departure. On its
            // next authenticated check-in, recover the missing checkout using the
            // Android-observed transition. Never accept future timestamps, timestamps
            // before this session's last confirmed heartbeat, or events on another day.
            // This is device-reported evidence; the existing router/device/geofence
            // checks ABOVE remain mandatory, and the raw event is audit-visible.
            if (attendance.CheckOutTime is null && awaySinceUtc is DateTime awayUtc)
            {
                var now = DateTime.UtcNow;
                awayUtc = awayUtc.Kind == DateTimeKind.Utc ? awayUtc : awayUtc.ToUniversalTime();
                var earliest = attendance.LastPingAt > attendance.CheckInTime
                    ? attendance.LastPingAt : attendance.CheckInTime;
                if (awayUtc < earliest) awayUtc = earliest;
                if (awayUtc > now) awayUtc = now;
                if (DateTimeExtensions.PakistanDateOf(awayUtc) == today &&
                    (now - awayUtc) >= TimeSpan.FromSeconds(5))
                {
                    attendance.CheckOutTime = awayUtc;
                    _db.LoginHistories.Add(new LoginHistory { UserId = user.Id,
                        EventType = LoginHistoryEvent.CheckOut, Timestamp = awayUtc,
                        Bssid = attendance.DeviceBssid });
                }
            }
            attendance.LastPingAt = DateTime.UtcNow;
            // Was only ever set on the day's first check-in, so every checkout after the
            // employee roamed to a different router (Logout, or the stale-checkout sweep)
            // kept logging that first router's name instead of the one they were actually
            // on — keeping this current is what DayHistory's Router column relies on.
            attendance.DeviceBssid = bssid;
            if (attendance.CheckOutTime is not null)
            {
                attendance.CheckOutTime = null;
                return (attendance, false, true);
            }
            return (attendance, false, false);
        }

        attendance = new Attendance
        {
            UserId = user.Id,
            Date = today,
            CheckInTime = DateTime.UtcNow,
            LastPingAt = DateTime.UtcNow,
            DeviceBssid = bssid
        };
        _db.Attendances.Add(attendance);
        return (attendance, true, false);
    }

    private static UserDto ToDto(User user) =>
        new()
        {
            Id = user.Id,
            Username = user.Username,
            FullName = user.FullName,
            Role = user.Role.ToString(),
            Department = user.Department.ToString(),
            ShiftStartTime = user.ShiftStartTime,
            ShiftEndTime = user.ShiftEndTime
        };

    private bool IsDevelopmentBrowserAdminRequest(bool requested, UserRole role)
    {
        if (!requested || !_environment.IsDevelopment() || !(AccessRules.IsBroadManager(role) || AccessRules.IsDepartmentHead(role)))
        {
            return false;
        }

        var origin = Request.Headers["Origin"].ToString();
        return Uri.TryCreate(origin, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback;
    }

    private LoginResponse CreateDevelopmentBrowserAdminResponse(User user) => new()
    {
        Token = _jwt.GenerateToken(user),
        User = ToDto(user),
        ReportSubmitted = false,
        AttendanceMarked = false,
        CheckInTime = DateTime.UtcNow
    };

    /// Great-circle distance in meters — mirrors what Geolocator.distanceBetween computes
    /// client-side, kept separately here so Login's inline geofence check doesn't depend on
    /// a round trip to a location that already reported in some other way.
    private static double DistanceMeters(double lat1, double lon1, double lat2, double lon2)
    {
        const double earthRadiusMeters = 6371000;
        double ToRad(double deg) => deg * Math.PI / 180;
        var dLat = ToRad(lat2 - lat1);
        var dLon = ToRad(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(ToRad(lat1)) * Math.Cos(ToRad(lat2)) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return earthRadiusMeters * c;
    }

    private int GetUserId() =>
        int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
