using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.DTOs.Admin;
using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

/// <summary>
/// Admin-only endpoints, gated by the <b>Admin role</b> on the caller's JWT (not a shared API key any
/// more). Only an account whose <c>Role = Admin</c> can reach these — generate activation codes, expire
/// plans, reset devices/passwords, and list every user's plan for the admin dashboard.
/// </summary>
[Authorize(Roles = "Admin")]
[Route("api/admin")]
public class AdminController : ApiControllerBase
{
    private readonly IAdminRepository _adminRepository;

    public AdminController(IAdminRepository adminRepository)
    {
        _adminRepository = adminRepository;
    }

    // GET: api/admin/users  → every account + its live plan snapshot (the admin dashboard feed)
    [HttpGet("users")]
    public async Task<IActionResult> ListUsers()
        => HandleResponse(await _adminRepository.ListUsersAsync());

    // POST: api/admin/activation-codes  → mint code(s) (phone-bound, minute-precise duration + expiry)
    [HttpPost("activation-codes")]
    public async Task<IActionResult> GenerateCodes([FromBody] GenerateActivationCodesDto dto)
        => HandleResponse(await _adminRepository.GenerateCodesAsync(dto));

    // POST: api/admin/reset-device  → clear a customer's device binding so they can log in on a new phone
    [HttpPost("reset-device")]
    public async Task<IActionResult> ResetDevice([FromBody] ResetDeviceDto dto)
        => HandleResponse(await _adminRepository.ResetDeviceAsync(dto));

    // POST: api/admin/reset-password  → set a new password for a user who forgot theirs
    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordDto dto)
        => HandleResponse(await _adminRepository.ResetPasswordAsync(dto));

    // POST: api/admin/expire-plan  → force a user's plan to lapse (also handy for QA)
    [HttpPost("expire-plan")]
    public async Task<IActionResult> ExpirePlan([FromBody] ExpirePlanDto dto)
        => HandleResponse(await _adminRepository.ExpirePlanAsync(dto));
}
