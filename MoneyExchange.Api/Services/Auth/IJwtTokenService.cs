using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.Auth;

public record JwtToken(string AccessToken, DateTime ExpiresAtUtc);

/// <summary>Issues bearer tokens after a customer completes OTP verification.</summary>
public interface IJwtTokenService
{
    JwtToken CreateToken(Customer customer);
}
