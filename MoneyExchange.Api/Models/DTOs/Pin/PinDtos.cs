using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Pin;

/// <summary>Sets the app-lock PIN for the first time (only when none is set yet). Six digits.</summary>
public class SetPinDto
{
    [Required, RegularExpression(@"^\d{6}$", ErrorMessage = "PIN must be exactly 6 digits.")]
    public string Pin { get; set; } = string.Empty;
}

/// <summary>Changes an existing app-lock PIN: verify the current one, then set the new one.</summary>
public class UpdatePinDto
{
    [Required, RegularExpression(@"^\d{6}$", ErrorMessage = "Current PIN must be 6 digits.")]
    public string CurrentPin { get; set; } = string.Empty;

    [Required, RegularExpression(@"^\d{6}$", ErrorMessage = "New PIN must be exactly 6 digits.")]
    public string NewPin { get; set; } = string.Empty;
}

/// <summary>Verifies an entered PIN against the stored hash (server-side unlock check).</summary>
public class VerifyPinDto
{
    [Required, RegularExpression(@"^\d{6}$", ErrorMessage = "PIN must be 6 digits.")]
    public string Pin { get; set; } = string.Empty;
}

/// <summary>Whether the signed-in user has set an app-lock PIN yet.</summary>
public class PinStatusDto
{
    public bool HasPin { get; set; }
}
