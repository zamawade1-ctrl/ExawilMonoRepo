using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>
/// Sign-up payload. The customer registers with just their <b>full name, phone number, and
/// password</b> — email/username were dropped. The account is usable immediately (the 3-day trial
/// starts at sign-up); the 6-digit app-lock PIN is set right after, on first entry.
/// </summary>
public class RegisterAccountDto
{
    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    /// <summary>The login identity. Unique. Stored trimmed/normalized by the repository.</summary>
    [Required, MaxLength(20), MinLength(6)]
    public string PhoneNumber { get; set; } = string.Empty;

    [Required, MinLength(6), MaxLength(128)]
    public string Password { get; set; } = string.Empty;

    /// <summary>
    /// A stable id for the device signing up (hash of Android <c>ANDROID_ID</c>). The account is
    /// bound to it so the same credentials can't later sign in from another phone. Optional (e.g.
    /// iOS / a client that can't provide one) — when absent, no device is bound at sign-up.
    /// </summary>
    [MaxLength(128)]
    public string? DeviceId { get; set; }

    /// <summary>Human-readable device label (e.g. "Samsung SM-A065F"), stored for support.</summary>
    [MaxLength(120)]
    public string? DeviceLabel { get; set; }
}
