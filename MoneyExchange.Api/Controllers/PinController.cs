using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.DTOs.Pin;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

/// <summary>
/// The custom 6-digit app-lock PIN endpoints, all scoped to the signed-in user. The PIN gates opening
/// the app (it replaced the device-credential lock) and is stored as a PBKDF2 hash on the User.
/// </summary>
[Authorize]
[Route("api/pin")]
public class PinController : ApiControllerBase
{
    private readonly IPinRepository _pinRepository;

    public PinController(IPinRepository pinRepository)
    {
        _pinRepository = pinRepository;
    }

    // GET: api/pin/status  → { hasPin }
    [HttpGet("status")]
    public async Task<IActionResult> Status()
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _pinRepository.GetStatusAsync(userId));
    }

    // POST: api/pin/set  → sets the PIN for the first time
    [HttpPost("set")]
    public async Task<IActionResult> Set([FromBody] SetPinDto dto)
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _pinRepository.SetPinAsync(userId, dto));
    }

    // POST: api/pin/verify  → checks an entered PIN
    [HttpPost("verify")]
    public async Task<IActionResult> Verify([FromBody] VerifyPinDto dto)
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _pinRepository.VerifyPinAsync(userId, dto));
    }

    // POST: api/pin/update  → verify current PIN, then set a new one
    [HttpPost("update")]
    public async Task<IActionResult> Update([FromBody] UpdatePinDto dto)
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _pinRepository.UpdatePinAsync(userId, dto));
    }
}
