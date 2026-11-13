using System.Security.Cryptography;
using System.Text;
namespace ScholarshipHive.Server.Services;
public static class CallingFormSharing
{
    public static string CreateToken() => Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
    public static string HashToken(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();
    public static bool ValidToken(string? token) => token is { Length: 64 } && token.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    public static string Link(HttpRequest request, string token)
    {
        // Railway terminates HTTPS before forwarding to Kestrel. Never emit a
        // public http:// link because Kestrel may see the internal hop as HTTP.
        var configured = Environment.GetEnvironmentVariable("PUBLIC_BASE_URL")?.TrimEnd('/');
        var isLocal = request.Host.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
                      request.Host.Host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase);
        var root = !string.IsNullOrWhiteSpace(configured) ? configured : isLocal
            ? $"{request.Scheme}://{request.Host}"
            : "https://scholarshiphive-backend-production-526c0ddb.up.railway.app";
        return $"{root}/shared/calling-form/{token}";
    }
}
