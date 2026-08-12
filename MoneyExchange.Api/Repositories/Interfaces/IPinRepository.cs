using MoneyExchange.Api.Models.DTOs.Pin;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

/// <summary>
/// Manages the custom 6-digit <b>app-lock PIN</b> that gates opening the app (replacing the old
/// device-credential lock). The PIN is stored as a PBKDF2 hash on the <c>User</c>; only the signed-in
/// user can read/set/change their own.
/// </summary>
public interface IPinRepository
{
    /// <summary>Whether the user has set an app-lock PIN yet.</summary>
    Task<ServiceResponse<PinStatusDto>> GetStatusAsync(int userId);

    /// <summary>Sets the PIN for the first time. Fails if one is already set (use update instead).</summary>
    Task<ServiceResponse<PinStatusDto>> SetPinAsync(int userId, SetPinDto dto);

    /// <summary>Verifies an entered PIN against the stored hash.</summary>
    Task<ServiceResponse<bool>> VerifyPinAsync(int userId, VerifyPinDto dto);

    /// <summary>Changes the PIN after verifying the current one.</summary>
    Task<ServiceResponse<PinStatusDto>> UpdatePinAsync(int userId, UpdatePinDto dto);
}
