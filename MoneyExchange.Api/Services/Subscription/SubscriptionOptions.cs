namespace MoneyExchange.Api.Services.Subscription;

/// <summary>
/// Config for the trial + paid plan, bound from the <c>Subscription</c> section of configuration.
/// The trial length is deliberately short (2 minutes) during development so the expiry/payment gate
/// can be exercised quickly; set <see cref="TrialMinutes"/> to 4320 (3 days) for production.
/// </summary>
public class SubscriptionOptions
{
    public const string SectionName = "Subscription";

    /// <summary>How long the free trial lasts, in minutes. Dev: 2. Production: 4320 (3 days).</summary>
    public int TrialMinutes { get; set; } = 2;

    /// <summary>How long a single payment grants Pro access, in days.</summary>
    public int PlanDays { get; set; } = 30;
}
