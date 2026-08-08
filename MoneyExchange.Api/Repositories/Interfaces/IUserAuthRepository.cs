using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

public interface IUserAuthRepository
{
    Task<ServiceResponse<UserAuthResponseDto>> SignInWithGoogleAsync(GoogleSignInDto dto);

    /// <summary>
    /// Permanently deletes the signed-in user's account and all data tied to it
    /// (their forwarding <see cref="Models.Entities.Customer"/> profile included).
    /// Required for app-store publishing (Google Play / App Store account-deletion policy).
    /// </summary>
    Task<ServiceResponse<bool>> DeleteAccountAsync(int userId);
}
