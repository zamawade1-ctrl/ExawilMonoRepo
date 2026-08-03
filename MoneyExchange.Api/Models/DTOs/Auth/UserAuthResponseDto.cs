namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>Returned after a successful Google sign-in.</summary>
public class UserAuthResponseDto
{
    public string AccessToken { get; set; } = string.Empty;

    public DateTime ExpiresAtUtc { get; set; }

    public int UserId { get; set; }

    public string Email { get; set; } = string.Empty;

    public string FullName { get; set; } = string.Empty;

    public string? ProfilePictureUrl { get; set; }
}
