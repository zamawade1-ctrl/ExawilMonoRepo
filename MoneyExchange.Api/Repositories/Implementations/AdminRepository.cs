using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Admin;
using MoneyExchange.Api.Models.DTOs.Subscription;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services;
using MoneyExchange.Api.Services.Subscription;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// Admin operations: mint activation codes and reset device bindings. Locked behind the admin API
/// role at the controller ([Authorize(Roles="Admin")]), so no customer JWT can reach these.
/// </summary>
public class AdminRepository : IAdminRepository
{
    // Unambiguous alphabet (no 0/O/1/I) so codes are easy to read aloud / type from WhatsApp.
    private const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private const string CodePrefix = "MX";
    private const int RandomLength = 12;          // 12 chars over a 31-char alphabet ≈ 59 bits
    private const int MaxBatch = 100;
    private const int DefaultExpiryMinutes = 14 * 24 * 60;   // 14 days

    private readonly AppDbContext _context;
    private readonly PlanCalculator _planCalculator;
    private readonly IPasswordHasher<User> _passwordHasher;
    private readonly ILogger<AdminRepository> _logger;

    public AdminRepository(
        AppDbContext context,
        PlanCalculator planCalculator,
        IPasswordHasher<User> passwordHasher,
        ILogger<AdminRepository> logger)
    {
        _context = context;
        _planCalculator = planCalculator;
        _passwordHasher = passwordHasher;
        _logger = logger;
    }

    public async Task<ServiceResponse<List<ActivationCodeDto>>> GenerateCodesAsync(GenerateActivationCodesDto dto)
    {
        try
        {
            // Duration in minutes (precise): a "Forever" code overrides everything with the sentinel;
            // otherwise explicit minutes win, else days→minutes, else the plan default.
            var durationMinutes = dto.Forever == true
                ? PlanKinds.ForeverMinutes
                : dto.DurationMinutes is int dm && dm > 0
                    ? dm
                    : dto.DurationDays is int dd && dd > 0
                        ? dd * 24 * 60
                        : _planCalculator.PlanDays * 24 * 60;
            var planKind = PlanKinds.Label(durationMinutes);

            // Billing amount comes straight from the client: "Forever · $200" and "Free unlimited" are
            // both the never-expires plan and differ only in the price sent (200 vs 0), so trust it
            // rather than forcing $0 for every Forever code (which would zero the paid Forever plan too).
            // null = unpriced/legacy; 0 = free plan (free-unlimited).
            var priceUsd = dto.PriceUsd;

            var count = Math.Clamp(dto.Count ?? 1, 1, MaxBatch);
            var assignedPhone = PhoneNumberUtil.Normalize(dto.Phone);
            var assigned = assignedPhone.Length > 0 ? assignedPhone : null;

            // Expiry in minutes: explicit minutes win, else days→minutes, else default; 0 = never.
            var expiryMinutes = dto.ExpiresInMinutes ?? (dto.ExpiresInDays is int ed ? ed * 24 * 60 : DefaultExpiryMinutes);
            var now = DateTime.UtcNow;
            DateTime? expiresAt = expiryMinutes > 0 ? now.AddMinutes(expiryMinutes) : null;

            var results = new List<ActivationCodeDto>(count);
            for (var i = 0; i < count; i++)
            {
                string raw;
                do
                {
                    raw = GenerateRaw();
                }
                while (await _context.ActivationCodes.AnyAsync(c => c.Code == raw));

                var activation = new ActivationCode
                {
                    Code = raw,
                    DurationMinutes = durationMinutes,
                    DurationDays = durationMinutes / (24 * 60),   // whole-day count, for display only
                    PriceUsd = priceUsd,   // admin billing amount; null = unpriced, 0 = free plan (incl. free-unlimited)
                    AssignedToPhone = assigned,
                    ExpiresAtUtc = expiresAt,
                    CreatedAtUtc = now
                };
                await _context.ActivationCodes.AddAsync(activation);

                results.Add(new ActivationCodeDto
                {
                    Code = ActivationCodeFormat.Prettify(raw),   // dashed form for readability; redeem tolerates either
                    DurationMinutes = durationMinutes,
                    DurationDays = durationMinutes / (24 * 60),
                    PlanKind = planKind,
                    AssignedToPhone = assigned,
                    ExpiresAtUtc = expiresAt
                });
            }

            await _context.SaveChangesAsync();

            _logger.LogInformation(
                "Admin generated {Count} code(s), {Minutes} min, assigned={Assigned}, expires={Expires}.",
                count, durationMinutes, assigned ?? "(bearer)", expiresAt?.ToString("o") ?? "(never)");
            return ServiceResponse<List<ActivationCodeDto>>.CreatedResult(results, "Activation code(s) generated.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Admin failed to generate activation codes.");
            return ServiceResponse<List<ActivationCodeDto>>.Error("Could not generate activation codes.");
        }
    }

    public async Task<ServiceResponse<ResetDeviceResultDto>> ResetDeviceAsync(ResetDeviceDto dto)
    {
        try
        {
            var phone = PhoneNumberUtil.Normalize(dto.Phone);
            if (phone.Length == 0)
                return ServiceResponse<ResetDeviceResultDto>.BadRequest("A phone number is required.");

            var user = await _context.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone);
            if (user is null)
                return ServiceResponse<ResetDeviceResultDto>.NotFound("No account with that phone number.");

            var previousLabel = user.DeviceLabel;
            user.DeviceId = null;
            user.DeviceLabel = null;
            user.DeviceRegisteredAtUtc = null;
            user.LastModifiedAtUtc = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            _logger.LogInformation("Admin reset device binding for user {UserId} ({Phone}).", user.Id, phone);
            return ServiceResponse<ResetDeviceResultDto>.Ok(
                new ResetDeviceResultDto
                {
                    UserId = user.Id,
                    Phone = user.PhoneNumber,
                    PreviousDeviceLabel = previousLabel
                },
                "Device binding cleared. The next login on any phone will bind that device.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Admin failed to reset device binding.");
            return ServiceResponse<ResetDeviceResultDto>.Error("Could not reset the device binding.");
        }
    }

    public async Task<ServiceResponse<PlanStatusDto>> ExpirePlanAsync(ExpirePlanDto dto)
    {
        try
        {
            var phone = PhoneNumberUtil.Normalize(dto.Phone);
            if (phone.Length == 0)
                return ServiceResponse<PlanStatusDto>.BadRequest("A phone number is required.");

            var user = await _context.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone);
            if (user is null)
                return ServiceResponse<PlanStatusDto>.NotFound("No account with that phone number.");

            var now = DateTime.UtcNow;
            var seconds = Math.Max(0, dto.InSeconds ?? 0);
            // Move the paid window to (now + N seconds) and push the trial start well into the past so
            // the account isn't kept alive by a lingering trial — it lapses to Expired at the boundary.
            user.PlanPaidUntilUtc = now.AddSeconds(seconds);
            user.PlanStartedAtUtc = now;
            user.TrialStartedAtUtc = now.AddYears(-1);
            user.LastModifiedAtUtc = now;
            await _context.SaveChangesAsync();

            _logger.LogInformation("Admin set plan for user {UserId} to expire in {Seconds}s.", user.Id, seconds);
            return ServiceResponse<PlanStatusDto>.Ok(
                _planCalculator.Snapshot(user),
                seconds == 0 ? "Plan expired now." : $"Plan will expire in {seconds}s.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Admin failed to expire plan.");
            return ServiceResponse<PlanStatusDto>.Error("Could not expire the plan.");
        }
    }

    public async Task<ServiceResponse<bool>> ResetPasswordAsync(ResetPasswordDto dto)
    {
        try
        {
            var phone = PhoneNumberUtil.Normalize(dto.Phone);
            if (phone.Length == 0)
                return ServiceResponse<bool>.BadRequest("A phone number is required.");
            if (dto.NewPassword.Length < 6)
                return ServiceResponse<bool>.BadRequest("New password must be at least 6 characters.");

            var user = await _context.Users.FirstOrDefaultAsync(u => u.PhoneNumber == phone);
            if (user is null)
                return ServiceResponse<bool>.NotFound("No account with that phone number.");

            user.PasswordHash = _passwordHasher.HashPassword(user, dto.NewPassword);
            user.LastModifiedAtUtc = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            _logger.LogInformation("Admin reset password for user {UserId}.", user.Id);
            return ServiceResponse<bool>.Ok(true, "Password reset. The user can now sign in with it and change it themselves.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Admin failed to reset password.");
            return ServiceResponse<bool>.Error("Could not reset the password.");
        }
    }

    public async Task<ServiceResponse<bool>> UpdatePhoneAsync(UpdatePhoneDto dto)
    {
        try
        {
            var current = PhoneNumberUtil.Normalize(dto.Phone);
            var next = PhoneNumberUtil.Normalize(dto.NewPhone);
            if (current.Length == 0 || next.Length == 0)
                return ServiceResponse<bool>.BadRequest("Both the current and new phone numbers are required.");

            var user = await _context.Users
                .Include(u => u.Customer)
                .FirstOrDefaultAsync(u => u.PhoneNumber == current);
            if (user is null)
                return ServiceResponse<bool>.NotFound("No account with that phone number.");

            if (next != current)
            {
                var taken = await _context.Users.AnyAsync(u => u.PhoneNumber == next && u.Id != user.Id);
                if (taken)
                    return ServiceResponse<bool>.BadRequest("Another account already uses that phone number.");
            }

            user.PhoneNumber = next;
            if (user.Customer is not null) user.Customer.PhoneNumber = next;
            user.LastModifiedAtUtc = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            _logger.LogInformation("Admin updated phone for user {UserId}: {Old} → {New}.", user.Id, current, next);
            return ServiceResponse<bool>.Ok(true, "Phone number updated.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Admin failed to update phone number.");
            return ServiceResponse<bool>.Error("Could not update the phone number.");
        }
    }

    public async Task<ServiceResponse<List<AdminUserDto>>> ListUsersAsync()
    {
        try
        {
            // Most-recently-edited first: last admin action / redemption, falling back to creation.
            var users = await _context.Users
                .OrderByDescending(u => u.LastModifiedAtUtc ?? u.CreatedAt)
                .ToListAsync();

            // Batch-load the newest activation code per phone (one query, grouped in memory) so the
            // table can show whether each customer has used the code they were issued — and when it was
            // issued — without an N+1 lookup. Codes are stored against the normalized phone.
            var phones = users
                .Select(u => PhoneNumberUtil.Normalize(u.PhoneNumber))
                .Where(p => p.Length > 0)
                .Distinct()
                .ToList();
            var latestCodeByPhone = (await _context.ActivationCodes
                    .Where(c => c.AssignedToPhone != null && phones.Contains(c.AssignedToPhone))
                    .ToListAsync())
                .GroupBy(c => c.AssignedToPhone!)
                .ToDictionary(
                    g => g.Key,
                    g => g.OrderByDescending(c => c.CreatedAtUtc).ThenByDescending(c => c.Id).First());

            var rows = users.Select(u =>
            {
                latestCodeByPhone.TryGetValue(PhoneNumberUtil.Normalize(u.PhoneNumber), out var code);
                return new AdminUserDto
                {
                    UserId = u.Id,
                    FullName = u.FullName,
                    Phone = u.PhoneNumber,
                    Role = u.Role.ToString(),
                    DeviceLabel = u.DeviceLabel,
                    HasDevice = !string.IsNullOrEmpty(u.DeviceId),
                    CreatedAtUtc = u.CreatedAt,
                    LastLoginAtUtc = u.LastLoginAtUtc,
                    LastModifiedAtUtc = u.LastModifiedAtUtc ?? u.CreatedAt,
                    PlanKind = PlanKinds.Label(u.PlanDurationMinutes),
                    PlanPriceUsd = u.PlanPriceUsd,
                    PlanStartedAtUtc = u.PlanStartedAtUtc,
                    Plan = _planCalculator.Snapshot(u),
                    LatestCodeGeneratedAtUtc = code?.CreatedAtUtc,
                    LatestCodeRedeemed = code?.IsRedeemed ?? false,
                    LatestCodeRedeemedAtUtc = code?.RedeemedAtUtc,
                };
            }).ToList();

            return ServiceResponse<List<AdminUserDto>>.Ok(rows);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Admin failed to list users.");
            return ServiceResponse<List<AdminUserDto>>.Error("Could not load users.");
        }
    }

    /// <summary>Builds the stored (dash-free, upper-case) code: prefix + N random chars.</summary>
    private static string GenerateRaw()
    {
        var sb = new StringBuilder(CodePrefix, CodePrefix.Length + RandomLength);
        for (var i = 0; i < RandomLength; i++)
            sb.Append(CodeAlphabet[RandomNumberGenerator.GetInt32(CodeAlphabet.Length)]);
        return sb.ToString();
    }
}
