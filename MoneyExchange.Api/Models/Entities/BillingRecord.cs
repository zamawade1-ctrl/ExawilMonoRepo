using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A permanent billing/sales ledger row, written once each time an admin generates an activation
/// code for a customer. This is the <b>historical</b> record of every plan sold — unlike the live
/// plan fields on <see cref="User"/> (which only reflect the customer's <i>current</i> plan and get
/// overwritten on the next redemption), a <see cref="BillingRecord"/> is never mutated away, so the
/// admin billing view can show revenue across every month, not just the plan each user holds today.
///
/// One row is created at code-generation time (the moment of the sale, after the customer paid out
/// of band); the row is later flagged <see cref="IsRedeemed"/> when/if the customer activates the
/// code, but it counts toward revenue from the instant it was minted regardless.
/// </summary>
public class BillingRecord
{
    public int Id { get; set; }

    /// <summary>The activation code this billing row was minted for (one-to-one with the code).</summary>
    public int ActivationCodeId { get; set; }

    public ActivationCode? ActivationCode { get; set; }

    /// <summary>
    /// The account this sale is for, resolved from the code's assigned phone at generation time, or
    /// null for a bearer code (no phone) / a phone with no account yet. Filled in on redemption if it
    /// was still null then.
    /// </summary>
    public int? UserId { get; set; }

    public User? User { get; set; }

    /// <summary>The customer's phone the code was issued to (normalized), or null for a bearer code.</summary>
    [MaxLength(20)]
    public string? Phone { get; set; }

    /// <summary>
    /// Snapshot of the customer's name at the time of sale, so the billing table reads correctly even
    /// if the account is later renamed or deleted. Null/"" for a bearer code with no known account.
    /// </summary>
    [MaxLength(200)]
    public string? CustomerName { get; set; }

    /// <summary>
    /// USD amount billed for this sale, copied from the code's <see cref="ActivationCode.PriceUsd"/>.
    /// Null = unpriced/legacy code (counts as 0 in revenue); 0 = an explicit free plan.
    /// </summary>
    public int? AmountUsd { get; set; }

    /// <summary>The plan-kind label at sale time ("1 month", "6 months", "1 year", "Forever", ...).</summary>
    [Required, MaxLength(40)]
    public string PlanKind { get; set; } = string.Empty;

    /// <summary>Minutes of Pro access the sold code grants when redeemed.</summary>
    public int DurationMinutes { get; set; }

    /// <summary>When the sale was recorded (= when the admin generated the code). Drives the month/day billing breakdown.</summary>
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    /// <summary>True once the customer has actually redeemed the code this row represents.</summary>
    public bool IsRedeemed { get; set; }

    /// <summary>When the code was redeemed, or null if it's still unused.</summary>
    public DateTime? RedeemedAtUtc { get; set; }
}
