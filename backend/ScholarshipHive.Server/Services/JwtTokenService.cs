using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Services;

public class JwtTokenService
{
    private readonly IConfiguration _config;

    public JwtTokenService(IConfiguration config)
    {
        _config = config;
    }

    public string GenerateToken(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_config["Jwt:Key"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.Username),
            new(ClaimTypes.Role, user.Role.ToString()),
            // A reset of HomeDeviceId invalidates previously issued employee JWTs.
            new("bound_device_id", user.Role == UserRole.Employee ? user.HomeDeviceId ?? "" : ""),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var expiryMinutes = _config.GetValue<int?>("Jwt:ExpiryMinutes") ?? 720;

        var token = new JwtSecurityToken(
            issuer: _config["Jwt:Issuer"] ?? "ScholarshipHive",
            audience: _config["Jwt:Audience"] ?? "ScholarshipHiveMobile",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(expiryMinutes),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
