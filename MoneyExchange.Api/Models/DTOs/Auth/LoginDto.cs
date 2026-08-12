using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>
/// Sign-in payload: phone number + password. (Sign-up now collects only full name, phone, and
/// password, so the phone is the login identity.)
/// </summary>
public class LoginDto
{
    [Required, MaxLength(20)]
    public string PhoneNumber { get; set; } = string.Empty;

    [Required, MaxLength(128)]
    public string Password { get; set; } = string.Empty;

    /// <summary>
    /// A stable id for the device signing in (hash of Android <c>ANDROID_ID</c>). Must match the
    /// device the account is bound to; a mismatch is rejected so credentials can't be used on another
    /// phone. Optional — an account with no bound device yet binds to the first id presented.
    /// </summary>
    [MaxLength(128)]
    public string? DeviceId { get; set; }

    /// <summary>Human-readable device label (e.g. "Samsung SM-A065F"), stored on first bind.</summary>
    [MaxLength(120)]
    public string? DeviceLabel { get; set; }
}
