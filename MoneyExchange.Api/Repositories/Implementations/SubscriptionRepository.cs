using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services;
using MoneyExchange.Api.Services.Subscription;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// Reads plan status and redeems activation codes. Redeeming a valid, unused code sets the user's
/// <see cref="User.PlanPaidUntilUtc"/> forward by the code's duration (extending from the current
/// paid-until if the plan is still active, otherwise from now), which flips the user back to Pro.
/// Generation is <b>not</b> here — it's admin-only (see <c>AdminRepository</c>).
/// </summary>
public class SubscriptionRepository : ISubscriptionRepository
{
    private readonly AppDbContext _context;
    private readonly PlanCalculator _planCalculator;
    private readonly ILogger<SubscriptionRepository> _logger;

    public SubscriptionRepository(
        AppDbContext context,
        PlanCalculator planCalculator,
        ILogger<SubscriptionRepository> logger)
    {
        _context = context;
        _planCalculator = planCalculator;
        _logger = logger;
    }

    public async Task<ServiceResponse<PlanStatusDto>> GetStatusAsync(int userId)
    {
        var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return ServiceResponse<PlanStatusDto>.NotFound("Account not found.");

        return ServiceResponse<PlanStatusDto>.Ok(_planCalculator.Snapshot(user));
    }

    public async Task<ServiceResponse<PlanStatusDto>> RedeemAsync(int userId, RedeemActivationDto dto)
    {
        try
        {
            // Accept the code however the customer types it: dashes/spaces stripped, upper-cased,
            // so "mx-4kpa-9qtr-7whx" matches the stored "MX4KPA9QTR7WHX".
            var code = NormalizeCode(dto.Code);
            if (code.Length == 0)
                return ServiceResponse<PlanStatusDto>.BadRequest("Enter an activation code.");

            var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
            if (user is null)
                return ServiceResponse<PlanStatusDto>.NotFound("Account not found.");

            var activation = await _context.ActivationCodes.FirstOrDefaultAsync(c => c.Code == code);
            if (activation is null)
                return ServiceResponse<PlanStatusDto>.BadRequest("Invalid activation code.");
            if (activation.IsRedeemed)
                return ServiceResponse<PlanStatusDto>.BadRequest("This activation code has already been used.");

            var now = DateTime.UtcNow;

            // Code shelf life: an unredeemed code past its expiry is dead.
            if (activation.ExpiresAtUtc is DateTime expires && expires < now)
                return ServiceResponse<PlanStatusDto>.BadRequest("This activation code has expired.");

            // Phone binding: a code issued to a specific number can only be redeemed by that account,
            // so a leaked/forwarded code is useless to anyone else.
            if (!string.IsNullOrEmpty(activation.AssignedToPhone) &&
                activation.AssignedToPhone != PhoneNumberUtil.Normalize(user.PhoneNumber))
            {
                return ServiceResponse<PlanStatusDto>.BadRequest(
                    "This activation code was issued to a different phone number.");
            }
            // Extend from the current paid-until if the plan is still live, else start fresh from now.
            var stillActive = user.PlanPaidUntilUtc is DateTime paid && paid > now;
            var start = stillActive ? user.PlanPaidUntilUtc!.Value : now;
            // Grant minutes (precise) — fall back to days for codes minted before DurationMinutes existed.
            var grantMinutes = activation.DurationMinutes > 0
                ? activation.DurationMinutes
                : activation.DurationDays * 24 * 60;
            user.PlanPaidUntilUtc = start.AddMinutes(grantMinutes);
            // Anchor the progress ring: begin a fresh period from now when the plan was inactive; keep
            // the existing start when merely extending an active plan.
            if (!stillActive || user.PlanStartedAtUtc is null)
                user.PlanStartedAtUtc = now;

            activation.IsRedeemed = true;
            activation.RedeemedByUserId = userId;
            activation.RedeemedAtUtc = now;

            await _context.SaveChangesAsync();

            _logger.LogInformation(
                "User {UserId} redeemed activation code {CodeId} for {Minutes} min (paid until {Until:o}).",
                userId, activation.Id, grantMinutes, user.PlanPaidUntilUtc);
            return ServiceResponse<PlanStatusDto>.Ok(_planCalculator.Snapshot(user), "Plan activated.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to redeem activation code for user {UserId}.", userId);
            return ServiceResponse<PlanStatusDto>.Error("Could not activate your plan.");
        }
    }

    /// <summary>Strips dashes/spaces and upper-cases a code so redemption tolerates how it's typed.</summary>
    internal static string NormalizeCode(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return string.Empty;
        return new string(code.Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant();
    }
}
