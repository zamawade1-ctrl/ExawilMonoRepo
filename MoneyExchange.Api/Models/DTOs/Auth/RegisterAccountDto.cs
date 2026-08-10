using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>
/// Sign-up payload for the phone/password auth flow that replaced Google Sign-In.
/// Collects the identity a customer logs in with. The Telesom OTP second factor is a
/// follow-up (the API isn't available yet), so no code is required here for now.
/// </summary>
public class RegisterAccountDto
{
    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [Required, EmailAddress, MaxLength(320)]
    public string Email { get; set; } = string.Empty;

    [Required, MaxLength(60), MinLength(3)]
    public string Username { get; set; } = string.Empty;

    [Required, MinLength(6), MaxLength(128)]
    public string Password { get; set; } = string.Empty;

    /// <summary>
    /// Optional. Reserved for the future Telesom OTP second factor and server-side receipt
    /// matching. The on-device forwarder reads the account's own number off the *800# balance
    /// screen, so the app doesn't require it at sign-up.
    /// </summary>
    [MaxLength(20)]
    public string? PhoneNumber { get; set; }
}
