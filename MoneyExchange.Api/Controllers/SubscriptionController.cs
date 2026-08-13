using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

/// <summary>
/// Trial/plan status + activation-code redemption, scoped to the signed-in user. When a trial or paid
/// plan lapses the app gates every page to the activation screen; redeeming a valid code re-opens Pro
/// access and lets on-device forwarding run again.
/// </summary>
[Authorize]
[Route("api/subscription")]
public class SubscriptionController : ApiControllerBase
{
    private readonly ISubscriptionRepository _subscriptionRepository;

    public SubscriptionController(ISubscriptionRepository subscriptionRepository)
    {
        _subscriptionRepository = subscriptionRepository;
    }

    // GET: api/subscription/status  → { status, trialEndsAtUtc, planPaidUntilUtc, serverNowUtc }
    [HttpGet("status")]
    public async Task<IActionResult> Status()
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _subscriptionRepository.GetStatusAsync(userId));
    }

    // GET: api/subscription/session?deviceId=  → { valid, reason, plan } for the app's fast session poll.
    // valid=false once the device was reset/rebound → the app signs out in near-real-time.
    [HttpGet("session")]
    public async Task<IActionResult> Session([FromQuery] string? deviceId)
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _subscriptionRepository.GetSessionAsync(userId, deviceId));
    }

    // POST: api/subscription/redeem  → consumes an activation code, returns the new plan status
    [HttpPost("redeem")]
    public async Task<IActionResult> Redeem([FromBody] RedeemActivationDto dto)
    {
        if (!TryGetAuthenticatedUserId(out var userId)) return Forbid();
        return HandleResponse(await _subscriptionRepository.RedeemAsync(userId, dto));
    }

    // Code generation lives in AdminController (admin-key protected). Users can only redeem — the
    // old open POST /api/subscription/generate was removed so customers can't mint their own codes.
}
