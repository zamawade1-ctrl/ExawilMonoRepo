using MoneyExchange.Api.Models.DTOs.Admin;
using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

/// <summary>
/// Admin-only operations, reached through <c>AdminController</c> behind the admin API key. The
/// business owner is the single trust anchor: he mints activation codes (handed to customers out of
/// band, e.g. WhatsApp) and resets device bindings when a customer legitimately switches phones.
/// </summary>
public interface IAdminRepository
{
    /// <summary>Mints one or more activation codes, optionally bound to a buyer's phone + with an expiry.</summary>
    Task<ServiceResponse<List<ActivationCodeDto>>> GenerateCodesAsync(GenerateActivationCodesDto dto);

    /// <summary>Clears a customer's device binding so their next login (on any device) re-binds.</summary>
    Task<ServiceResponse<ResetDeviceResultDto>> ResetDeviceAsync(ResetDeviceDto dto);

    /// <summary>QA: forces a user's plan (and trial) to lapse, optionally a few seconds out.</summary>
    Task<ServiceResponse<PlanStatusDto>> ExpirePlanAsync(ExpirePlanDto dto);

    /// <summary>Admin sets a new password for a user (forgot-password), identified by phone.</summary>
    Task<ServiceResponse<bool>> ResetPasswordAsync(ResetPasswordDto dto);

    /// <summary>Admin corrects a user's phone number (mistyped at sign-up), keeping it unique.</summary>
    Task<ServiceResponse<bool>> UpdatePhoneAsync(UpdatePhoneDto dto);

    /// <summary>All customer accounts with their live plan snapshot, for the admin dashboard.</summary>
    Task<ServiceResponse<List<AdminUserDto>>> ListUsersAsync();

    /// <summary>The full billing ledger (one row per activation code minted), newest sale first.</summary>
    Task<ServiceResponse<List<BillingRecordDto>>> ListBillingAsync();
}
