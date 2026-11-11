namespace ScholarshipHive.Server.Services;

/// Railway (like most cloud platforms) sits the app behind an edge proxy whose address
/// isn't fixed or published, so ASP.NET Core's built-in ForwardedHeadersMiddleware —
/// which only trusts a header coming from an explicitly known proxy IP/network — doesn't
/// apply cleanly here. This just takes the left-most (original client) entry from
/// X-Forwarded-For when present, falling back to the direct connection for local/direct
/// requests (e.g. plain `dotnet run` on a laptop, with no proxy in front at all).
public static class ClientIpResolver
{
    public static string? Resolve(HttpContext context)
    {
        var forwardedFor = context.Request.Headers["X-Forwarded-For"].ToString();
        if (!string.IsNullOrWhiteSpace(forwardedFor))
        {
            var first = forwardedFor.Split(',')[0].Trim();
            if (!string.IsNullOrEmpty(first)) return first;
        }
        return context.Connection.RemoteIpAddress?.ToString();
    }
}
