using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

[Route("api/auth")]
public class AuthController : ApiControllerBase
{
    private readonly IAuthRepository _authRepository;
    private readonly IUserAuthRepository _userAuthRepository;

    public AuthController(IAuthRepository authRepository, IUserAuthRepository userAuthRepository)
    {
        _authRepository = authRepository;
        _userAuthRepository = userAuthRepository;
    }

    // POST: api/auth/google
    // The Flutter app's first-page sign-in: exchanges a Google ID token for our own JWT.
    [HttpPost("google")]
    public async Task<IActionResult> SignInWithGoogle([FromBody] GoogleSignInDto dto)
    {
        var response = await _userAuthRepository.SignInWithGoogleAsync(dto);
        return HandleResponse(response);
    }

    // POST: api/auth/otp/request
    [HttpPost("otp/request")]
    public async Task<IActionResult> RequestOtp([FromBody] RequestOtpDto dto)
    {
        var response = await _authRepository.RequestOtpAsync(dto);
        return HandleResponse(response);
    }

    // POST: api/auth/otp/verify
    [HttpPost("otp/verify")]
    public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpDto dto)
    {
        var response = await _authRepository.VerifyOtpAsync(dto);
        return HandleResponse(response);
    }
}
