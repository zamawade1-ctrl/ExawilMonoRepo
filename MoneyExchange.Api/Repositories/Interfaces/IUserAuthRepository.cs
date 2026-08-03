using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

public interface IUserAuthRepository
{
    Task<ServiceResponse<UserAuthResponseDto>> SignInWithGoogleAsync(GoogleSignInDto dto);
}
