using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

public interface IUserAuthRepository
{
    /// <summary>
    /// Signs up: creates the <see cref="Models.Entities.User"/> identity (full name, email,
    /// username, hashed password) and its linked <see cref="Models.Entities.Customer"/>
    /// forwarding profile, then returns a signed-in JWT.
    /// </summary>
    Task<ServiceResponse<UserAuthResponseDto>> RegisterAsync(RegisterAccountDto dto);

    /// <summary>Verifies a username-or-email + password and returns a signed-in JWT.</summary>
    Task<ServiceResponse<UserAuthResponseDto>> LoginAsync(LoginDto dto);

    Task<ServiceResponse<UserAuthResponseDto>> SignInWithGoogleAsync(GoogleSignInDto dto);

    /// <summary>
    /// Permanently deletes the signed-in user's account and all data tied to it
    /// (their forwarding <see cref="Models.Entities.Customer"/> profile included).
    /// Required for app-store publishing (Google Play / App Store account-deletion policy).
    /// </summary>
    Task<ServiceResponse<bool>> DeleteAccountAsync(int userId);
}
