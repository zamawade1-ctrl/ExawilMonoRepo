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

/// <summary>Admin corrects a user's phone number (e.g. mistyped at sign-up), identified by their current phone.</summary>
public class UpdatePhoneDto
{
    /// <summary>The account's current (possibly wrong) phone number.</summary>
    [Required, MaxLength(20)]
    public string Phone { get; set; } = string.Empty;

    /// <summary>The corrected phone number to set.</summary>
    [Required, MaxLength(20)]
    public string NewPhone { get; set; } = string.Empty;
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

    /// <summary>When the account was last edited (admin action / redemption); drives list ordering.</summary>
    public DateTime LastModifiedAtUtc { get; set; }

    /// <summary>The paid-plan kind label ("1 month", "6 months", "1 year", "Forever"), or null if never paid.</summary>
    public string? PlanKind { get; set; }

    /// <summary>
    /// USD price of the plan the user redeemed, for the admin billing view. Distinguishes the $10 and
    /// $5 one-month plans that share a duration, and a $0 free plan. Null = unpriced/legacy (the admin
    /// UI falls back to the duration-derived price).
    /// </summary>
    public int? PlanPriceUsd { get; set; }

    /// <summary>When the current paid (Pro) period began, or null if the user has never paid. For the admin billing view.</summary>
    public DateTime? PlanStartedAtUtc { get; set; }

    public PlanStatusDto Plan { get; set; } = new();

    /// <summary>
    /// When the most recent activation code was generated for this account, or null if none has ever
    /// been minted. Lets the admin table show "issued a code at &lt;time&gt;" — the moment of hand-off,
    /// distinct from when (if ever) the plan actually starts counting on redemption.
    /// </summary>
    public DateTime? LatestCodeGeneratedAtUtc { get; set; }

    /// <summary>
    /// Whether that most recent code has been redeemed. False means "issued but not used yet", so the
    /// admin can see a customer who was given a code but hasn't activated — and the plan hasn't begun.
    /// </summary>
    public bool LatestCodeRedeemed { get; set; }

    /// <summary>
    /// When the most recent code was redeemed (the instant the plan duration actually started
    /// counting), or null if it's still unused. Null + a non-null generated-at = "waiting to be used".
    /// </summary>
    public DateTime? LatestCodeRedeemedAtUtc { get; set; }
}
