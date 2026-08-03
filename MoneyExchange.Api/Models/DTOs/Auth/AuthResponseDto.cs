namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>Returned after a successful OTP verification.</summary>
public class AuthResponseDto
{
    public string AccessToken { get; set; } = string.Empty;

    public DateTime ExpiresAtUtc { get; set; }

    public int CustomerId { get; set; }

    public string FullName { get; set; } = string.Empty;

    public string PhoneNumber { get; set; } = string.Empty;
}