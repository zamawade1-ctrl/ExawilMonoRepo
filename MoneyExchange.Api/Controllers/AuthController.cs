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

    // POST: api/auth/register
    // The app's sign-up form: full name, email, username, password. Creates the User identity +
    // its linked Customer forwarding profile and returns a signed-in JWT (no OTP for now).
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterAccountDto dto)
    {
        var response = await _userAuthRepository.RegisterAsync(dto);
        return HandleResponse(response);
    }

    // POST: api/auth/login
    // The app's sign-in form: username-or-email + password. Returns a JWT on success.
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginDto dto)
    {
        var response = await _userAuthRepository.LoginAsync(dto);
        return HandleResponse(response);
    }

    // POST: api/auth/google
    // Legacy Google sign-in, kept dormant since the switch to phone/password auth. Not used by
    // the app any more; left in place so existing tokens / the verifier still compile.
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

    // POST: api/auth/password  — the signed-in user changes their own password (current + new).
    [Authorize]
    [HttpPost("password")]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordDto dto)
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _userAuthRepository.ChangePasswordAsync(userId, dto));
    }

    // POST: api/auth/pin-enabled  — turn the app-lock PIN requirement on or off (returns a fresh session).
    [Authorize]
    [HttpPost("pin-enabled")]
    public async Task<IActionResult> SetPinEnabled([FromBody] SetPinEnabledDto dto)
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _userAuthRepository.SetPinEnabledAsync(userId, dto.Enabled));
    }

    // DELETE: api/auth/me
    // Permanently deletes the signed-in customer's account and all associated data.
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
