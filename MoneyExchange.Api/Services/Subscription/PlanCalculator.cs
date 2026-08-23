using Microsoft.Extensions.Options;
using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.Subscription;

/// <summary>
/// Derives a <see cref="PlanStatus"/> (and a client-facing <see cref="PlanStatusDto"/> snapshot)
/// from a user's trial window + any paid plan, using the configured <see cref="SubscriptionOptions"/>
/// (trial length is a short 2 minutes in dev, 3 days in production).
/// </summary>
public class PlanCalculator
{
    private readonly SubscriptionOptions _options;

    public PlanCalculator(IOptions<SubscriptionOptions> options)
    {
        _options = options.Value;
    }

    /// <summary>
    /// When the free trial ends: the trial-start time plus the configured trial length — unless the
    /// trial was already consumed on this device (<see cref="User.TrialConsumed"/>), in which case it
    /// ended the instant it started, so a re-registered account gets no fresh trial window.
    /// </summary>
    public DateTime TrialEndsAt(User user) =>
        user.TrialConsumed
            ? user.TrialStartedAtUtc
            : user.TrialStartedAtUtc.AddMinutes(_options.TrialMinutes);

    /// <summary>The user's access state at <paramref name="nowUtc"/>: Pro > Trial > Expired.</summary>
    public PlanStatus StatusFor(User user, DateTime nowUtc)
    {
        if (user.PlanPaidUntilUtc is DateTime paidUntil && paidUntil > nowUtc)
            return PlanStatus.Pro;
        if (nowUtc < TrialEndsAt(user))
            return PlanStatus.Trial;
        return PlanStatus.Expired;
    }

    /// <summary>Builds the client-facing snapshot (status + timestamps) for the given user.</summary>
    public PlanStatusDto Snapshot(User user)
    {
        var now = DateTime.UtcNow;
        var status = StatusFor(user, now);

        // The active window's bounds, for the client's progress ring.
        DateTime? periodStart = null;
        DateTime? periodEnd = null;
        switch (status)
        {
            case PlanStatus.Pro:
                periodEnd = user.PlanPaidUntilUtc;
                // Anchor to the recorded plan start; fall back to a plan-length window if unknown
                // (older accounts predating PlanStartedAtUtc).
                periodStart = user.PlanStartedAtUtc
                    ?? user.PlanPaidUntilUtc?.AddDays(-_options.PlanDays);
                break;
            case PlanStatus.Trial:
                periodStart = user.TrialStartedAtUtc;
                periodEnd = TrialEndsAt(user);
                break;
            case PlanStatus.Expired:
                break;
        }

        return new PlanStatusDto
        {
            Status = status.ToString(),
            TrialEndsAtUtc = TrialEndsAt(user),
            PlanPaidUntilUtc = user.PlanPaidUntilUtc,
            ServerNowUtc = now,
            PlanDays = _options.PlanDays,
            CurrentPeriodStartUtc = periodStart,
            CurrentPeriodEndUtc = periodEnd
        };
    }

    /// <summary>How many days a single activation/payment grants.</summary>
    public int PlanDays => _options.PlanDays;
}
