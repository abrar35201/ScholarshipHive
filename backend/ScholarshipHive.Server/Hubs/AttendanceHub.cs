using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace ScholarshipHive.Server.Hubs;

/// Push-only: the server broadcasts "DataChanged" events (see RealtimeNotifier) and
/// clients just listen and refetch via the existing REST endpoints — no client-invokable
/// methods needed. Web connects via the cookie session, mobile via its JWT.
[Authorize(AuthenticationSchemes = $"{CookieAuthenticationDefaults.AuthenticationScheme},{JwtBearerDefaults.AuthenticationScheme}")]
public class AttendanceHub : Hub
{
}
