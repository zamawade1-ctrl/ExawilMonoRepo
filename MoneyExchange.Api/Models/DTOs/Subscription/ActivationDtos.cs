using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Subscription;

/// <summary>Redeems an activation code to (re)open Pro access for the signed-in user.</summary>
public class RedeemActivationDto
{
    [Required, MaxLength(32)]
    public string Code { get; set; } = string.Empty;
}

/// <summary>
/// Admin request to mint one or more activation codes (see <c>AdminController</c>). Generation is an
/// admin-only concern — codes are handed to customers out of band (e.g. WhatsApp) after payment.
/// </summary>
public class GenerateActivationCodesDto
{
    /// <summary>
    /// The buyer's phone number to bind the code(s) to, so only that account can redeem them. Leave
    /// null/empty to mint bearer codes anyone can redeem.
    /// </summary>
    [MaxLength(20)]
    public string? Phone { get; set; }

    /// <summary>Days of Pro access each code grants. Optional alternative to <see cref="DurationMinutes"/>.</summary>
    public int? DurationDays { get; set; }

    /// <summary>
    /// Minutes of Pro access each code grants — the precise unit (so a 2-minute test code is possible).
    /// Takes precedence over <see cref="DurationDays"/>. If neither is given, the configured plan length.
    /// </summary>
    public int? DurationMinutes { get; set; }

    /// <summary>How many codes to mint (1–100). Defaults to 1.</summary>
    public int? Count { get; set; }

    /// <summary>
    /// When true, mint a never-expiring "Forever" plan code — overrides the duration fields with
    /// <c>PlanKinds.ForeverMinutes</c> so redemption sets the plan ~4000 years out.
    /// </summary>
    public bool? Forever { get; set; }

    /// <summary>Days until the code(s) expire if unredeemed. Optional alternative to <see cref="ExpiresInMinutes"/>.</summary>
    public int? ExpiresInDays { get; set; }

    /// <summary>
    /// Minutes until the code(s) expire if unredeemed. Takes precedence over <see cref="ExpiresInDays"/>.
    /// Defaults to 14 days; pass 0 for no expiry.
    /// </summary>
    public int? ExpiresInMinutes { get; set; }
}

/// <summary>
/// A freshly generated activation code, returned by the admin generate endpoint so it can be handed
/// to a customer.
/// </summary>
public class ActivationCodeDto
{
    public string Code { get; set; } = string.Empty;
    public int DurationDays { get; set; }
    public int DurationMinutes { get; set; }

    /// <summary>Human plan-kind label ("1 month", "6 months", "1 year", "Forever", or a custom duration).</summary>
    public string? PlanKind { get; set; }

    public string? AssignedToPhone { get; set; }
    public DateTime? ExpiresAtUtc { get; set; }
}
