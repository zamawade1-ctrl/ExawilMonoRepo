using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Models.Entities;
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

    public async Task<ServiceResponse<SessionStatusDto>> GetSessionAsync(int userId, string? deviceId)
    {
        var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return ServiceResponse<SessionStatusDto>.Ok(
                new SessionStatusDto { Valid = false, Reason = "account-not-found" });

        // The session is valid while the caller's device still matches the account's bound device.
        // When the client presents no device id (iOS/tests) the lock isn't enforced → treat as valid.
        // After an admin device-reset the bound DeviceId is cleared, so a previously-bound device now
        // mismatches → invalid → the app signs out and the account can re-bind on the next login.
        var deviceValid = string.IsNullOrEmpty(deviceId) || user.DeviceId == deviceId;

        return ServiceResponse<SessionStatusDto>.Ok(new SessionStatusDto
        {
            Valid = deviceValid,
            Reason = deviceValid ? null : "device-reset",
            Plan = _planCalculator.Snapshot(user),
            // Deliver any admin-minted code waiting for this account on the same poll, so it lands on
            // the user's activation page in near-real-time and clears itself once redeemed.
            PendingCode = await FindPendingCodeAsync(user, DateTime.UtcNow),
        });
    }

    /// <summary>
    /// The newest activation code minted for this exact account (bound to the user's phone) that is
    /// still redeemable — unredeemed and unexpired — or null when none is waiting. Because the query
    /// filters out redeemed codes, a code the user already consumed stops surfacing until the admin
    /// mints a fresh one; because it's phone-bound, it only ever reaches the one account it's for.
    /// </summary>
    private async Task<PendingActivationCodeDto?> FindPendingCodeAsync(User user, DateTime now)
    {
        var phone = PhoneNumberUtil.Normalize(user.PhoneNumber);
        if (phone.Length == 0) return null;

        var code = await _context.ActivationCodes
            .Where(c => c.AssignedToPhone == phone
                && !c.IsRedeemed
                && (c.ExpiresAtUtc == null || c.ExpiresAtUtc > now))
            .OrderByDescending(c => c.CreatedAtUtc)
            .ThenByDescending(c => c.Id)
            .FirstOrDefaultAsync();
        if (code is null) return null;

        // Fall back to days for codes minted before DurationMinutes existed (mirrors RedeemAsync).
        var grantMinutes = code.DurationMinutes > 0 ? code.DurationMinutes : code.DurationDays * 24 * 60;
        return new PendingActivationCodeDto
        {
            Code = ActivationCodeFormat.Prettify(code.Code),
            PlanKind = PlanKinds.Label(grantMinutes),
            DurationMinutes = grantMinutes,
            ExpiresAtUtc = code.ExpiresAtUtc,
            CreatedAtUtc = code.CreatedAtUtc,
        };
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
            // Record the granted duration (drives the admin "plan kind" label) and mark as edited.
            user.PlanDurationMinutes = grantMinutes;
            // Carry the code's price so the admin billing view shows the exact amount (distinguishes the
            // $10 vs $5 one-month plans, and a $0 free plan). Null on a legacy/unpriced code.
            user.PlanPriceUsd = activation.PriceUsd;
            user.LastModifiedAtUtc = now;

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
