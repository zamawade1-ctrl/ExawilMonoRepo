using System.ComponentModel.DataAnnotations;
using MoneyExchange.Api.Models.DTOs.Subscription;

namespace MoneyExchange.Api.Models.DTOs.Admin;

/// <summary>Admin request to clear a customer's device binding so they can sign in on a new phone.</summary>
public class ResetDeviceDto
{
    /// <summary>The customer's phone number (their login identity).</summary>
    [Required, MaxLength(20)]
    public string Phone { get; set; } = string.Empty;
}

/// <summary>Result of an admin device reset: who was reset and the label of the device that was bound.</summary>
public class ResetDeviceResultDto
{
    public int UserId { get; set; }
    public string? Phone { get; set; }
    public string? PreviousDeviceLabel { get; set; }
}

/// <summary>
/// QA helper: forces a user's plan to expire (optionally a few seconds out) so the app's real-time
/// expiry→activation redirect can be exercised without waiting days for a real Pro plan to lapse.
/// </summary>
public class ExpirePlanDto
{
    /// <summary>The customer's phone number (their login identity).</summary>
    [Required, MaxLength(20)]
    public string Phone { get; set; } = string.Empty;

    /// <summary>Seconds from now until the plan lapses (default 0 = expire immediately).</summary>
    public int? InSeconds { get; set; }
}

/// <summary>Admin sets a new password for a user (forgot-password flow), identified by phone.</summary>
public class ResetPasswordDto
{
    [Required, MaxLength(20)]
    public string Phone { get; set; } = string.Empty;

    [Required, MinLength(6), MaxLength(128)]
    public string NewPassword { get; set; } = string.Empty;
}

/// <summary>One row of the admin "all users" view: identity + their live plan snapshot.</summary>
public class AdminUserDto
{
    public int UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? Phone { get; set; }
    public string Role { get; set; } = "User";
    public string? DeviceLabel { get; set; }
    public bool HasDevice { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime LastLoginAtUtc { get; set; }
    public PlanStatusDto Plan { get; set; } = new();
}
