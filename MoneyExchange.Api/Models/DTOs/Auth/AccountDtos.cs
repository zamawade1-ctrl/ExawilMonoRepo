using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>The signed-in user changing their own password (current password required).</summary>
public class ChangePasswordDto
{
    [Required, MaxLength(128)]
    public string CurrentPassword { get; set; } = string.Empty;

    [Required, MinLength(6), MaxLength(128)]
    public string NewPassword { get; set; } = string.Empty;
}

/// <summary>Toggle the app-lock PIN requirement on/off for the signed-in user.</summary>
public class SetPinEnabledDto
{
    public bool Enabled { get; set; }
}
