using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Hubs;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpContextAccessor();

builder.Services.AddControllersWithViews()
    .AddJsonOptions(options => options.JsonSerializerOptions.Converters.Add(new UtcDateTimeConverter()));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddSignalR();
builder.Services.AddAntiforgery(options => options.HeaderName = "X-CSRF-TOKEN");

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options => options.AddPolicy("LocalFlutterDevelopment", policy => policy
        .SetIsOriginAllowed(origin =>
            Uri.TryCreate(origin, UriKind.Absolute, out var uri) &&
            uri.Scheme == Uri.UriSchemeHttp &&
            uri.IsLoopback)
        .AllowAnyHeader()
        .AllowAnyMethod()
        .AllowCredentials()));
}

// PostgreSQL is the sole runtime database provider. SQLite is supported only as
// a read-only legacy source by the separate migration utility (tools/).
var databaseConnectionString = builder.Configuration.GetConnectionString("DefaultConnection");
if (string.IsNullOrWhiteSpace(databaseConnectionString))
    throw new InvalidOperationException(
        "PostgreSQL connection is missing. Set ConnectionStrings:DefaultConnection in dotnet user-secrets or ConnectionStrings__DefaultConnection in deployment environment.");
builder.Services.AddDbContext<AppDbContext>(options => options.UseNpgsql(databaseConnectionString));

// Persisted to Postgres (via AppDbContext) rather than the container's own local
// disk — that disk resets on every deploy/restart, which was silently invalidating
// every already-open web session's login antiforgery token (and any other
// encrypted cookie) the moment a fresh container came up. That surfaced as a
// login that hangs or fails right after submitting the form, for anyone whose
// browser still had the previous deployment's login page open.
builder.Services.AddDataProtection()
    .PersistKeysToDbContext<AppDbContext>()
    .SetApplicationName("ScholarshipHive");

builder.Services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();
builder.Services.AddScoped<JwtTokenService>();
builder.Services.AddScoped<NetworkAccessService>();
builder.Services.AddScoped<AiAssistantService>();
builder.Services.AddScoped<DashboardAnalyticsService>();
builder.Services.AddScoped<AnalyticsService>();
builder.Services.AddScoped<AttendanceDurationService>();
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<UserActiveStatusCache>();
builder.Services.AddHttpClient();
// Railway's containers appear to have no working IPv6 egress, but DNS for
// generativelanguage.googleapis.com still returns AAAA records — SocketsHttpHandler's
// default connect logic then tries IPv6 first and just hangs (no fast refusal) instead of
// falling back to IPv4, so the whole chat request stalls indefinitely. Force IPv4-only
// connections and a short connect timeout so a real network problem fails fast instead.
builder.Services.AddHttpClient("Gemini", client => client.Timeout = TimeSpan.FromSeconds(45))
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        ConnectTimeout = TimeSpan.FromSeconds(10),
        ConnectCallback = async (context, cancellationToken) =>
        {
            var entry = await System.Net.Dns.GetHostEntryAsync(context.DnsEndPoint.Host, cancellationToken);
            var ipv4 = entry.AddressList.FirstOrDefault(a => a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                ?? entry.AddressList.First();
            var socket = new System.Net.Sockets.Socket(System.Net.Sockets.SocketType.Stream, System.Net.Sockets.ProtocolType.Tcp)
            {
                NoDelay = true
            };
            try
            {
                await socket.ConnectAsync(ipv4, context.DnsEndPoint.Port, cancellationToken);
                return new System.Net.Sockets.NetworkStream(socket, ownsSocket: true);
            }
            catch
            {
                socket.Dispose();
                throw;
            }
        }
    });
builder.Services.AddSingleton<RealtimeNotifier>();
builder.Services.AddHostedService<StaleAttendanceCheckoutService>();
builder.Services.AddSingleton<FcmPushService>();
builder.Services.AddHostedService<FcmWakeService>();

// Throttles the anonymous auth endpoints (register/login, both API and web) per caller
// IP — now that the backend is reachable from the whole internet rather than just the
// office LAN, this bounds how fast someone could hammer them with automated/scripted
// requests. Everything else (authenticated API calls, admin pages) passes through
// unthrottled. Implemented as a single global limiter with path-based branching, rather
// than [EnableRateLimiting] attributes on each action, since those attributes weren't
// reliably engaging on these MVC controllers.
var authRateLimitedPaths = new[]
{
    "/api/auth/register",
    "/api/auth/register-reception",
    "/api/auth/remote-admin-login",
    "/api/leaves/apply",
    "/api/leaves/status",
    "/api/shift-requests/remote/apply",
    "/api/shift-requests/remote/mine",
    "/api/auth/login",
    "/api/auth/forgot-password",
    "/Account/Login"
};
const string checkNetworkPath = "/api/auth/check-network";

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
    {
        var path = httpContext.Request.Path.Value ?? "";
        var ip = ClientIpResolver.Resolve(httpContext) ?? "unknown";

        // Every signed-in phone polls this every ~15s (more with retries) to detect
        // Wi-Fi changes, all day, for as long as someone's logged in — and with many
        // employees sharing one office's public IP behind NAT, that adds up to far more
        // traffic than a login/register attempt ever would. It needs its own generous,
        // separate budget so normal attendance traffic never shares (and exhausts) the
        // much stricter budget below meant to guard against credential brute-forcing —
        // that was the bug: one shared 20/min bucket per IP meant a handful of employees
        // polling check-network could lock out everyone at that office from check-network,
        // login, AND register at once.
        if (path.Equals(checkNetworkPath, StringComparison.OrdinalIgnoreCase))
        {
            return RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: $"checknet:{ip}",
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 600,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0
                });
        }

        var isAuthLimited = authRateLimitedPaths.Any(p => path.Equals(p, StringComparison.OrdinalIgnoreCase));
        if (!isAuthLimited)
        {
            return RateLimitPartition.GetNoLimiter("unthrottled");
        }

        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: $"auth:{ip}",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 20,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            });
    });
});

var jwtKey = builder.Configuration["Jwt:Key"];
if (string.IsNullOrWhiteSpace(jwtKey) || Encoding.UTF8.GetByteCount(jwtKey) < 32)
    throw new InvalidOperationException("Set Jwt:Key to a unique secret of at least 32 UTF-8 bytes. Never ship the old development signing key.");
var jwtIssuer = builder.Configuration["Jwt:Issuer"] ?? "ScholarshipHive";
var jwtAudience = builder.Configuration["Jwt:Audience"] ?? "ScholarshipHiveMobile";

builder.Services.AddAuthentication(options =>
    {
        options.DefaultAuthenticateScheme = CookieAuthenticationDefaults.AuthenticationScheme;
        options.DefaultChallengeScheme = CookieAuthenticationDefaults.AuthenticationScheme;
    })
    .AddCookie(CookieAuthenticationDefaults.AuthenticationScheme, options =>
    {
        options.LoginPath = "/Account/Login";
        options.AccessDeniedPath = "/Account/AccessDenied";
        options.ExpireTimeSpan = TimeSpan.FromHours(8);
        options.SlidingExpiration = true;
        options.Events.OnValidatePrincipal = async context =>
        {
            var idClaim = context.Principal?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            var roleClaim = context.Principal?.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
            if (!int.TryParse(idClaim, out var userId)) { context.RejectPrincipal(); return; }
            var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
            var account = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId);
            if (account is null || !account.IsActive || !account.IsApproved || account.Role.ToString() != roleClaim)
                context.RejectPrincipal(); // revoked admin rights take effect on the next request
        };
    })
    .AddJwtBearer(JwtBearerDefaults.AuthenticationScheme, options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtIssuer,
            ValidAudience = jwtAudience,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ClockSkew = TimeSpan.FromMinutes(1)
        };
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = async context =>
            {
                // Every JWT must match the account's live role: a Marketing Head whose
                // admin access was revoked cannot keep using an old privileged token.
                var userIdValue = context.Principal?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
                if (!int.TryParse(userIdValue, out var userId)) { context.Fail("Invalid account"); return; }
                var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId);
                var tokenRole = context.Principal?.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
                if (user is null || !user.IsActive || !user.IsApproved || user.Role.ToString() != tokenRole)
                {
                    context.Fail("Account or role changed; sign in again");
                    return;
                }
                if (user.Role != UserRole.Employee) return;
                var device = context.Principal?.FindFirst("bound_device_id")?.Value;
                if (string.IsNullOrWhiteSpace(user.HomeDeviceId) || user.HomeDeviceId != device)
                    context.Fail("Device registration was reset; sign in again");
            },
            // Browsers/mobile SignalR clients can't set an Authorization header on the
            // WebSocket upgrade request, so the JS/Dart clients pass the JWT as a query
            // string param instead — this is the standard ASP.NET Core pattern for it.
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                if (!string.IsNullOrEmpty(accessToken) && context.Request.Path.StartsWithSegments("/hubs"))
                {
                    context.Token = accessToken;
                }
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("AdminOnly", policy =>
        policy.RequireRole(nameof(UserRole.Admin), nameof(UserRole.Auditor), nameof(UserRole.SuperAdmin), nameof(UserRole.Owner), nameof(UserRole.CountryHead))
              .AddAuthenticationSchemes(CookieAuthenticationDefaults.AuthenticationScheme));

    // Auditor has broad access (Users/Attendance/Reports/Audit Reports) but not
    // Network Settings or the AI Assistant — those two stay Admin-only.
    options.AddPolicy("AdminOnlyStrict", policy =>
        policy.RequireRole(nameof(UserRole.Admin), nameof(UserRole.SuperAdmin), nameof(UserRole.Owner), nameof(UserRole.CountryHead))
              .AddAuthenticationSchemes(CookieAuthenticationDefaults.AuthenticationScheme));
});

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("AnnouncementWeb", p => p.RequireRole("Admin", "SuperAdmin", "Owner", "CountryHead", "HeadOfMarketing", "Auditor", "HeadOfProcessing", "HeadOfCounselors", "Receptionist")
        .AddAuthenticationSchemes(CookieAuthenticationDefaults.AuthenticationScheme));
    options.AddPolicy("TeamHeadWeb", p => p.RequireRole("HeadOfMarketing", "HeadOfProcessing", "HeadOfCounselors")
        .AddAuthenticationSchemes(CookieAuthenticationDefaults.AuthenticationScheme));
});

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    // PostgreSQL migrations are the only schema authority. No EnsureCreated,
    // PRAGMA or SQLite CREATE TABLE patches execute in the application.
    // For old SQLite data: first run `dotnet ef database update` on an empty
    // PostgreSQL database, then use tools/migrate_sqlite_to_postgres.py BEFORE
    // the first application startup (the importer refuses nonempty targets).
    await db.Database.MigrateAsync();
    await DbSeeder.SeedAsync(db, scope.ServiceProvider.GetRequiredService<IPasswordHasher<User>>(), app.Configuration);
    // One-time, non-destructive role normalization for the reserved original admin.
    // Keep the existing password/hash, account ID, attendance and other data intact.
    var primaryAdmin = await db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == "admin");
    if (primaryAdmin != null && (primaryAdmin.Role != UserRole.Admin || !primaryAdmin.IsActive || !primaryAdmin.IsApproved))
    {
        primaryAdmin.Role = UserRole.Admin;
        primaryAdmin.IsActive = true;
        primaryAdmin.IsApproved = true;
        await db.SaveChangesAsync();
    }
    // Old SuperAdmin values can exist in saved databases. Convert them to normal
    // Admin roles, while the reserved username remains the sole protected account.
    var formerSuperAdmins = await db.Users.Where(u => u.Role == UserRole.SuperAdmin).ToListAsync();
    foreach (var account in formerSuperAdmins) account.Role = UserRole.Admin;
    if (formerSuperAdmins.Count > 0) await db.SaveChangesAsync();
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}
else
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// No forced HTTPS redirect: this app runs on the internal LAN and the mobile
// client talks to it over plain HTTP, so redirecting to the self-signed HTTPS
// endpoint would break it (the phone doesn't trust that dev certificate).
//
// The static file middleware 404s on any extension it doesn't recognize —
// .apk isn't one of the defaults, which silently broke serving the in-app
// update download (wwwroot/downloads/ScholarshipHive.apk) while the
// version.json next to it worked fine.
var staticFileContentTypes = new FileExtensionContentTypeProvider();
staticFileContentTypes.Mappings[".apk"] = "application/vnd.android.package-archive";
app.UseStaticFiles(new StaticFileOptions { ContentTypeProvider = staticFileContentTypes });

// In local development, serve the Flutter web release build under /mobile.
// The web-server debug target depends on a browser debug extension and leaves
// a blank page on phones; the release bundle works as a normal static site.
var mobileWebRoot = Path.GetFullPath(Path.Combine(
    app.Environment.ContentRootPath, "..", "..", "mobile", "build", "web"));
if (app.Environment.IsDevelopment() && Directory.Exists(mobileWebRoot))
{
    var mobileWebFiles = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(mobileWebRoot);
    app.UseDefaultFiles(new DefaultFilesOptions
    {
        FileProvider = mobileWebFiles,
        RequestPath = "/mobile"
    });
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = mobileWebFiles,
        RequestPath = "/mobile"
    });
}

app.UseRouting();
if (app.Environment.IsDevelopment())
    app.UseCors("LocalFlutterDevelopment");
app.UseRateLimiter();

app.UseAuthentication();

// Kill switch: an admin deactivating a user (or a password-reset invalidating
// their old credentials) should take effect on that person's very next
// request, not just their next login/checkin — a JWT is otherwise stateless
// and would keep authenticating a deactivated account for as long as the
// token itself remains unexpired (up to its full lifetime), even though
// every login/checkin call already re-checks IsActive. Checking Postgres
// directly on every single request added a DB round-trip to every API call
// in the app — UserActiveStatusCache keeps that lookup rare (short TTL) while
// EditUser/etc. still invalidate it immediately on deactivation, so a
// lost/stolen, still-logged-in phone is still cut off right away rather than
// only ever blocking its NEXT sign-in.
app.Use(async (context, next) =>
{
    if (context.User.Identity?.IsAuthenticated == true)
    {
        var idClaim = context.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (int.TryParse(idClaim, out var userId))
        {
            var statusCache = context.RequestServices.GetRequiredService<UserActiveStatusCache>();
            var stillActive = await statusCache.IsActiveAsync(userId, async () =>
            {
                var db = context.RequestServices.GetRequiredService<AppDbContext>();
                return await db.Users.Where(u => u.Id == userId).Select(u => u.IsActive).FirstOrDefaultAsync();
            });
            if (!stillActive)
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsync("Your account is no longer active. Please log in again.");
                return;
            }
        }
    }
    await next();
});

// Deny cross-department and owner-only requests regardless of what clients render.
// The database role is read per request so revocation is effective without a fresh login.
app.Use(async (ctx, next) =>
{
    if (ctx.User.Identity?.IsAuthenticated == true &&
        int.TryParse(ctx.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var actorId))
    {
        var db = ctx.RequestServices.GetRequiredService<AppDbContext>();
        var actor = await db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == actorId);
        if (actor == null || !actor.IsActive || !actor.IsApproved ||
            !ctx.User.IsInRole(actor.Role.ToString()))
            { ctx.Response.StatusCode = 401; return; }
        var path = ctx.Request.Path.Value ?? "";
        if (actor.Role == UserRole.Employee)
        {
            // Only a Calling employee may open the country-form draft workflow.
            // All its endpoints still independently validate caller scope.
            var callingFormsPath = actor.Department == EmployeeDepartment.Calling &&
                (path.Equals("/CallingForms", StringComparison.OrdinalIgnoreCase) ||
                 path.StartsWith("/CallingForms/", StringComparison.OrdinalIgnoreCase) ||
                 path.Equals("/api/calling-forms", StringComparison.OrdinalIgnoreCase) ||
                 path.StartsWith("/api/calling-forms/", StringComparison.OrdinalIgnoreCase));
            var allowed = callingFormsPath ||
                path.Equals("/ShiftRequests/Mine", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/ShiftRequests/Submit", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/Account/Logout", StringComparison.OrdinalIgnoreCase);
            if (!allowed)
            {
                if (path == "/" && HttpMethods.IsGet(ctx.Request.Method)) { ctx.Response.Redirect("/ShiftRequests/Mine"); return; }
                ctx.Response.StatusCode = 403; return;
            }
        }
        if (AccessRules.IsDepartmentHead(actor.Role))
        {
            var allowed = path.StartsWith("/TeamScope", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/ShiftRequests/Mine", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/ShiftRequests/Submit", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/team-scope", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/api/shift-requests/apply", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/api/shift-requests/mine", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/api/shift-requests/remote/apply", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/api/shift-requests/remote/mine", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/Announcements", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/announcements", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/auth", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/Account", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/hubs", StringComparison.OrdinalIgnoreCase);
            if (!allowed)
            {
                if (path == "/" && ctx.Request.Method == "GET" && ctx.User.Identity?.AuthenticationType == "Cookies")
                    { ctx.Response.Redirect("/TeamScope"); return; }
                ctx.Response.StatusCode = 403; return;
            }
        }
        if (actor.Role == UserRole.CountryHead)
        {
            var sensitive = path.StartsWith("/NetworkSettings", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/Chat", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/network", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/chat", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/Users/Create", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/Users/Edit", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/Users/Details", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/admin/routers", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/admin/locations", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/admin/pending-networks", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/admin/password-resets", StringComparison.OrdinalIgnoreCase) ||
                (path.StartsWith("/api/admin/users/", StringComparison.OrdinalIgnoreCase) &&
                 path.Contains("/detail", StringComparison.OrdinalIgnoreCase)) ||
                path.Contains("device", StringComparison.OrdinalIgnoreCase);
            var isNotice = path.StartsWith("/Announcements", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/announcements", StringComparison.OrdinalIgnoreCase);
            var isOwnShiftRequest = path.Equals("/ShiftRequests/Mine", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/ShiftRequests/Submit", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/api/shift-requests/apply", StringComparison.OrdinalIgnoreCase);
            isOwnShiftRequest = isOwnShiftRequest || path.Equals("/api/shift-requests/remote/apply", StringComparison.OrdinalIgnoreCase) ||
                path.Equals("/api/shift-requests/remote/mine", StringComparison.OrdinalIgnoreCase);
            if (sensitive || (!HttpMethods.IsGet(ctx.Request.Method) && !isNotice && !isOwnShiftRequest &&
                !path.StartsWith("/Account/Logout", StringComparison.OrdinalIgnoreCase) &&
                !path.StartsWith("/hubs", StringComparison.OrdinalIgnoreCase) &&
                !path.StartsWith("/api/auth", StringComparison.OrdinalIgnoreCase)))
                { ctx.Response.StatusCode = 403; return; }
        }
    }
    await next();
});

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.MapHub<AttendanceHub>("/hubs/attendance");

// Listen on all interfaces so phones on the same LAN/router (or, in the cloud, the
// hosting platform's edge proxy) can reach the API.
var cloudPort = Environment.GetEnvironmentVariable("PORT");
app.Urls.Clear();
if (!string.IsNullOrEmpty(cloudPort))
{
    // Cloud hosting (Railway, etc.) assigns the port and terminates HTTPS at its edge —
    // the container itself only needs to listen on plain HTTP internally.
    app.Urls.Add($"http://0.0.0.0:{cloudPort}");
}
else
{
    app.Urls.Add("http://0.0.0.0:5080");
}

app.Run();
