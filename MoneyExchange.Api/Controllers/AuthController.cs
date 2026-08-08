using Microsoft.AspNetCore.Authorization;
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

    // DELETE: api/auth/me
    // Permanently deletes the signed-in user's account and all associated data.
    // Required by the Google Play / App Store account-deletion policy for publishing.
    [Authorize]
    [HttpDelete("me")]
    public async Task<IActionResult> DeleteMyAccount()
    {
        if (!TryGetAuthenticatedUserId(out var userId))
            return Forbid();

        var response = await _userAuthRepository.DeleteAccountAsync(userId);
        return HandleResponse(response);
    }
}
