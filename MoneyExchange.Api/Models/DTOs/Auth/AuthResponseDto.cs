namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>
/// Returned after a successful sign-up, sign-in, or OTP verification. The Customer is the
/// authenticated identity now, so this carries its profile alongside the JWT.
/// </summary>
public class AuthResponseDto
{
    public string AccessToken { get; set; } = string.Empty;

    public DateTime ExpiresAtUtc { get; set; }

    public int CustomerId { get; set; }

    public string FullName { get; set; } = string.Empty;

    public string? Username { get; set; }

    public string? Email { get; set; }

    public string? PhoneNumber { get; set; }
}
