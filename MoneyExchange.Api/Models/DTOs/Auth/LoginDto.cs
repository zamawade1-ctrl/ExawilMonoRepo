using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>
/// Sign-in payload for the phone/password auth flow. The single field accepts either the
/// customer's username or their email - the repository figures out which. No OTP for now
/// (Telesom API pending); it becomes a first-login-only second factor later.
/// </summary>
public class LoginDto
{
    /// <summary>The customer's username or email address.</summary>
    [Required, MaxLength(320)]
    public string UsernameOrEmail { get; set; } = string.Empty;

    [Required, MaxLength(128)]
    public string Password { get; set; } = string.Empty;
}
