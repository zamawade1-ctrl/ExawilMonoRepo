namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>Returned after a successful sign-up, sign-in, or Google sign-in.</summary>
public class UserAuthResponseDto
{
    public string AccessToken { get; set; } = string.Empty;

    public DateTime ExpiresAtUtc { get; set; }

    public int UserId { get; set; }

    /// <summary>The forwarding profile created for / owned by this user (1-to-1).</summary>
    public int? CustomerId { get; set; }

    public string Email { get; set; } = string.Empty;

    public string? Username { get; set; }

    public string FullName { get; set; } = string.Empty;

    public string? ProfilePictureUrl { get; set; }
}
