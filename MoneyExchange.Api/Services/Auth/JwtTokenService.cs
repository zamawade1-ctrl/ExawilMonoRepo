using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.Auth;

public class JwtTokenService : IJwtTokenService
{
    private readonly IConfiguration _configuration;

    public JwtTokenService(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public JwtToken CreateToken(Customer customer) => CreateToken(
        customer.Id.ToString(),
        // PhoneNumber is nullable; coalesce to "" since a Claim value can't be null.
        [new Claim("phoneNumber", customer.PhoneNumber ?? string.Empty), new Claim("subjectType", "customer")]);

    public JwtToken CreateToken(User user) => CreateToken(
        user.Id.ToString(),
        [new Claim("email", user.Email), new Claim("username", user.Username ?? string.Empty), new Claim("subjectType", "user")]);

    private JwtToken CreateToken(string subject, IEnumerable<Claim> extraClaims)
    {
        var jwtSection = _configuration.GetSection("Jwt");
        var key = jwtSection["Key"] ?? throw new InvalidOperationException("Jwt:Key is not configured.");
        var issuer = jwtSection["Issuer"];
        var audience = jwtSection["Audience"];
        var expiryMinutes = jwtSection.GetValue("ExpiryMinutes", 60);

        var expiresAtUtc = DateTime.UtcNow.AddMinutes(expiryMinutes);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, subject),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };
        claims.AddRange(extraClaims);

        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)),
            SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            expires: expiresAtUtc,
            signingCredentials: credentials);

        return new JwtToken(new JwtSecurityTokenHandler().WriteToken(token), expiresAtUtc);
    }
}
