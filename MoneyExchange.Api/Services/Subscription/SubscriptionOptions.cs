namespace MoneyExchange.Api.Services.Subscription;

/// <summary>
/// Config for the trial + paid plan, bound from the <c>Subscription</c> section of configuration.
/// The free trial is <b>2 days</b> (2880 minutes).
/// </summary>
public class SubscriptionOptions
{
    public const string SectionName = "Subscription";

    /// <summary>How long the free trial lasts, in minutes. Default 2880 (2 days).</summary>
    public int TrialMinutes { get; set; } = 2880;

    /// <summary>How long a single payment grants Pro access, in days.</summary>
    public int PlanDays { get; set; } = 30;
}
