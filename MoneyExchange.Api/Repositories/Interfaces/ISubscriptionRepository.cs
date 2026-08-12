using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

/// <summary>
/// Reads a user's trial/plan status and redeems activation codes. When a trial or paid plan lapses
/// the app gates to the activation page; redeeming a valid code re-opens Pro access for
/// <c>SubscriptionOptions.PlanDays</c> days.
/// </summary>
public interface ISubscriptionRepository
{
    /// <summary>The signed-in user's current plan snapshot (status + trial/plan timestamps).</summary>
    Task<ServiceResponse<PlanStatusDto>> GetStatusAsync(int userId);

    /// <summary>Redeems a one-time activation code, extending/opening the user's Pro plan.</summary>
    Task<ServiceResponse<PlanStatusDto>> RedeemAsync(int userId, RedeemActivationDto dto);
}
