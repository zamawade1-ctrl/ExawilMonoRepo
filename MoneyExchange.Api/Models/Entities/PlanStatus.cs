namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// The access state a <see cref="User"/> is in, derived from their trial window and any paid plan.
/// </summary>
public enum PlanStatus
{
    /// <summary>Inside the free-trial window; access is granted and a countdown is shown.</summary>
    Trial = 0,

    /// <summary>Trial elapsed and no active paid plan; the app is gated to the payment page.</summary>
    Expired = 1,

    /// <summary>A paid plan is active (<see cref="User.PlanPaidUntilUtc"/> in the future).</summary>
    Pro = 2
}
