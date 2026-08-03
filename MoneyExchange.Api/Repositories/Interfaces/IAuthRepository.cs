using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

public interface IAuthRepository
{
    Task<ServiceResponse<bool>> RequestOtpAsync(RequestOtpDto dto);

    Task<ServiceResponse<AuthResponseDto>> VerifyOtpAsync(VerifyOtpDto dto);
}
