using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Pin;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// Stores/verifies the custom 6-digit app-lock PIN as a PBKDF2 hash (same hasher used for passwords)
/// on the signed-in user's <see cref="User.AppPinHash"/>. The raw PIN never leaves the request; only
/// its hash is persisted.
/// </summary>
public class PinRepository : IPinRepository
{
    private readonly AppDbContext _context;
    private readonly IPasswordHasher<User> _passwordHasher;
    private readonly ILogger<PinRepository> _logger;

    public PinRepository(
        AppDbContext context,
        IPasswordHasher<User> passwordHasher,
        ILogger<PinRepository> logger)
    {
        _context = context;
        _passwordHasher = passwordHasher;
        _logger = logger;
    }

    public async Task<ServiceResponse<PinStatusDto>> GetStatusAsync(int userId)
    {
        var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return ServiceResponse<PinStatusDto>.NotFound("Account not found.");

        return ServiceResponse<PinStatusDto>.Ok(
            new PinStatusDto { HasPin = !string.IsNullOrEmpty(user.AppPinHash) });
    }

    public async Task<ServiceResponse<PinStatusDto>> SetPinAsync(int userId, SetPinDto dto)
    {
        try
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
            if (user is null)
                return ServiceResponse<PinStatusDto>.NotFound("Account not found.");
            if (!string.IsNullOrEmpty(user.AppPinHash))
                return ServiceResponse<PinStatusDto>.Conflict("A PIN is already set. Use update instead.");

            user.AppPinHash = _passwordHasher.HashPassword(user, dto.Pin);
            await _context.SaveChangesAsync();

            _logger.LogInformation("User {UserId} set their app-lock PIN.", userId);
            return ServiceResponse<PinStatusDto>.Ok(new PinStatusDto { HasPin = true }, "PIN set.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to set PIN for user {UserId}.", userId);
            return ServiceResponse<PinStatusDto>.Error("Could not set your PIN.");
        }
    }

    public async Task<ServiceResponse<bool>> VerifyPinAsync(int userId, VerifyPinDto dto)
    {
        var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user?.AppPinHash is null)
            return ServiceResponse<bool>.BadRequest("No PIN is set.");

        var result = _passwordHasher.VerifyHashedPassword(user, user.AppPinHash, dto.Pin);
        if (result == PasswordVerificationResult.Failed)
            return ServiceResponse<bool>.BadRequest("Incorrect PIN.");

        if (result == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.AppPinHash = _passwordHasher.HashPassword(user, dto.Pin);
            await _context.SaveChangesAsync();
        }
        return ServiceResponse<bool>.Ok(true, "PIN verified.");
    }

    public async Task<ServiceResponse<PinStatusDto>> UpdatePinAsync(int userId, UpdatePinDto dto)
    {
        try
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
            if (user?.AppPinHash is null)
                return ServiceResponse<PinStatusDto>.BadRequest("No PIN is set yet.");

            var check = _passwordHasher.VerifyHashedPassword(user, user.AppPinHash, dto.CurrentPin);
            if (check == PasswordVerificationResult.Failed)
                return ServiceResponse<PinStatusDto>.BadRequest("Your current PIN is incorrect.");

            user.AppPinHash = _passwordHasher.HashPassword(user, dto.NewPin);
            await _context.SaveChangesAsync();

            _logger.LogInformation("User {UserId} changed their app-lock PIN.", userId);
            return ServiceResponse<PinStatusDto>.Ok(new PinStatusDto { HasPin = true }, "PIN updated.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to update PIN for user {UserId}.", userId);
            return ServiceResponse<PinStatusDto>.Error("Could not update your PIN.");
        }
    }
}
