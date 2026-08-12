using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services;
using MoneyExchange.Api.Services.Auth;
using MoneyExchange.Api.Services.Subscription;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// The identity/auth store. Handles username/password sign-up + sign-in (creating the
/// <see cref="User"/> and its linked <see cref="Customer"/> forwarding profile), the dormant
/// Google sign-in, and account deletion. Passwords are stored as PBKDF2 hashes via
/// <see cref="IPasswordHasher{T}"/>; no hosted auth provider (e.g. Supabase Auth) is involved.
/// </summary>
public class UserAuthRepository : IUserAuthRepository
{
    private readonly AppDbContext _context;
    private readonly IGoogleTokenVerifier _googleTokenVerifier;
    private readonly IJwtTokenService _tokenService;
    private readonly IPasswordHasher<User> _passwordHasher;
    private readonly PlanCalculator _planCalculator;
    private readonly ILogger<UserAuthRepository> _logger;

    public UserAuthRepository(
        AppDbContext context,
        IGoogleTokenVerifier googleTokenVerifier,
        IJwtTokenService tokenService,
        IPasswordHasher<User> passwordHasher,
        PlanCalculator planCalculator,
        ILogger<UserAuthRepository> logger)
    {
        _context = context;
        _googleTokenVerifier = googleTokenVerifier;
        _tokenService = tokenService;
        _passwordHasher = passwordHasher;
        _planCalculator = planCalculator;
        _logger = logger;
    }

    public async Task<ServiceResponse<UserAuthResponseDto>> RegisterAsync(RegisterAccountDto dto)
    {
        try
        {
            var fullName = dto.FullName.Trim();
            var phone = NormalizePhone(dto.PhoneNumber);

            if (fullName.Length == 0)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Full name is required.");
            if (phone.Length < 6)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Enter a valid phone number.");
            if (dto.Password.Length < 6)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Password must be at least 6 characters.");

            if (await _context.Users.AnyAsync(u => u.PhoneNumber == phone))
                return ServiceResponse<UserAuthResponseDto>.Conflict("An account with this phone number already exists.");

            var now = DateTime.UtcNow;
            var deviceId = (dto.DeviceId ?? string.Empty).Trim();

            // One account per device: if this phone already registered an account here, a *second*
            // person can't sign up on the same phone. (Admin device-reset frees it for re-use.)
            if (deviceId.Length > 0 && await _context.Users.AnyAsync(u => u.DeviceId == deviceId))
                return ServiceResponse<UserAuthResponseDto>.Conflict(
                    "This device is already registered to an account. Only one account per device is allowed.");
            var user = new User
            {
                FullName = fullName,
                PhoneNumber = phone,
                CreatedAt = now,
                LastLoginAtUtc = now,
                // Bind the account to the device it signed up on (when the client provided an id), so
                // the same credentials can't later be used to sign in from a different phone.
                DeviceId = deviceId.Length > 0 ? deviceId : null,
                DeviceLabel = deviceId.Length > 0 ? dto.DeviceLabel?.Trim() : null,
                DeviceRegisteredAtUtc = deviceId.Length > 0 ? now : null,
                // The free trial starts the moment the account is created.
                TrialStartedAtUtc = now,
                // The linked forwarding profile is created in the same transaction, so the User
                // and Customer tables are always populated together and related via Customer.UserId.
                Customer = new Customer
                {
                    FullName = fullName,
                    PhoneNumber = phone,
                    // OTP is bypassed for now (Telesom API pending), so the profile is treated as
                    // verified immediately and can receive auto-forwarding. Flip to false when OTP lands.
                    IsVerified = true,
                    CreatedAt = now
                }
            };
            user.PasswordHash = _passwordHasher.HashPassword(user, dto.Password);

            await _context.Users.AddAsync(user);
            await _context.SaveChangesAsync();

            _logger.LogInformation(
                "Registered user {UserId} ({Phone}) with linked customer {CustomerId}.",
                user.Id, user.PhoneNumber, user.Customer!.Id);
            return ServiceResponse<UserAuthResponseDto>.CreatedResult(BuildResponse(user), "Account created.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register account.");
            return ServiceResponse<UserAuthResponseDto>.Error("Could not create the account.");
        }
    }

    public async Task<ServiceResponse<UserAuthResponseDto>> LoginAsync(LoginDto dto)
    {
        try
        {
            var phone = NormalizePhone(dto.PhoneNumber);
            if (phone.Length == 0 || dto.Password.Length == 0)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Phone number and password are required.");

            var user = await _context.Users
                .Include(u => u.Customer)
                .FirstOrDefaultAsync(u => u.PhoneNumber == phone);

            // Same message for "no such account" and "wrong password" so callers can't probe.
            if (user?.PasswordHash is null)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Incorrect phone number or password.");

            var result = _passwordHasher.VerifyHashedPassword(user, user.PasswordHash, dto.Password);
            if (result == PasswordVerificationResult.Failed)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Incorrect phone number or password.");

            if (result == PasswordVerificationResult.SuccessRehashNeeded)
                user.PasswordHash = _passwordHasher.HashPassword(user, dto.Password);

            // Device lock: the account is tied to one phone. If it's already bound, a login from a
            // different device is refused (only an admin device-reset can move it). If it's not bound
            // yet (new field on a legacy account, or an admin just reset it), bind to this device now.
            var presentedDeviceId = (dto.DeviceId ?? string.Empty).Trim();
            if (!string.IsNullOrEmpty(user.DeviceId))
            {
                if (presentedDeviceId.Length > 0 && presentedDeviceId != user.DeviceId)
                {
                    _logger.LogWarning(
                        "Rejected login for user {UserId}: device mismatch (bound {Bound}, presented {Presented}).",
                        user.Id, user.DeviceId, presentedDeviceId);
                    return ServiceResponse<UserAuthResponseDto>.Conflict(
                        "This account is registered to another device. Contact support to move it to this phone.");
                }
            }
            else if (presentedDeviceId.Length > 0)
            {
                user.DeviceId = presentedDeviceId;
                user.DeviceLabel = dto.DeviceLabel?.Trim();
                user.DeviceRegisteredAtUtc = DateTime.UtcNow;
            }

            user.LastLoginAtUtc = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            _logger.LogInformation("User {UserId} signed in.", user.Id);
            return ServiceResponse<UserAuthResponseDto>.Ok(BuildResponse(user), "Signed in.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to sign in.");
            return ServiceResponse<UserAuthResponseDto>.Error("Could not sign in.");
        }
    }

    private UserAuthResponseDto BuildResponse(User user)
    {
        var token = _tokenService.CreateToken(user);
        return new UserAuthResponseDto
        {
            AccessToken = token.AccessToken,
            ExpiresAtUtc = token.ExpiresAtUtc,
            UserId = user.Id,
            CustomerId = user.Customer?.Id,
            Email = user.Email,
            Username = user.Username,
            PhoneNumber = user.PhoneNumber,
            FullName = user.FullName,
            ProfilePictureUrl = user.ProfilePictureUrl,
            HasAppPin = !string.IsNullOrEmpty(user.AppPinHash),
            PinEnabled = user.PinEnabled,
            Role = user.Role.ToString(),
            Plan = _planCalculator.Snapshot(user)
        };
    }

    /// <summary>Trims and strips spaces/dashes/parens from a phone number for consistent matching.</summary>
    private static string NormalizePhone(string? phone) => PhoneNumberUtil.Normalize(phone);

    public async Task<ServiceResponse<UserAuthResponseDto>> SignInWithGoogleAsync(GoogleSignInDto dto)
    {
        GoogleIdentity identity;
        try
        {
            identity = await _googleTokenVerifier.VerifyAsync(dto.IdToken);
        }
        catch (InvalidGoogleTokenException ex)
        {
            _logger.LogWarning(ex, "Rejected an invalid Google ID token.");
            return ServiceResponse<UserAuthResponseDto>.BadRequest("Invalid Google sign-in token.");
        }

        try
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.GoogleSubjectId == identity.Subject);

            if (user is null)
            {
                user = new User
                {
                    Email = identity.Email,
                    GoogleSubjectId = identity.Subject,
                    FullName = identity.FullName,
                    ProfilePictureUrl = identity.ProfilePictureUrl,
                    CreatedAt = DateTime.UtcNow,
                    LastLoginAtUtc = DateTime.UtcNow
                };
                await _context.Users.AddAsync(user);
            }
            else
            {
                user.Email = identity.Email;
                user.FullName = identity.FullName;
                user.ProfilePictureUrl = identity.ProfilePictureUrl;
                user.LastLoginAtUtc = DateTime.UtcNow;
            }

            await _context.SaveChangesAsync();

            return ServiceResponse<UserAuthResponseDto>.Ok(BuildResponse(user), "Signed in with Google.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to complete Google sign-in.");
            return ServiceResponse<UserAuthResponseDto>.Error("Could not complete Google sign-in.");
        }
    }

    public async Task<ServiceResponse<bool>> ChangePasswordAsync(int userId, ChangePasswordDto dto)
    {
        try
        {
            if (dto.NewPassword.Length < 6)
                return ServiceResponse<bool>.BadRequest("New password must be at least 6 characters.");

            var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
            if (user?.PasswordHash is null)
                return ServiceResponse<bool>.NotFound("Account not found.");

            var check = _passwordHasher.VerifyHashedPassword(user, user.PasswordHash, dto.CurrentPassword);
            if (check == PasswordVerificationResult.Failed)
                return ServiceResponse<bool>.BadRequest("Your current password is incorrect.");

            user.PasswordHash = _passwordHasher.HashPassword(user, dto.NewPassword);
            await _context.SaveChangesAsync();

            _logger.LogInformation("User {UserId} changed their password.", userId);
            return ServiceResponse<bool>.Ok(true, "Password updated.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to change password for user {UserId}.", userId);
            return ServiceResponse<bool>.Error("Could not change your password.");
        }
    }

    public async Task<ServiceResponse<UserAuthResponseDto>> SetPinEnabledAsync(int userId, bool enabled)
    {
        try
        {
            var user = await _context.Users
                .Include(u => u.Customer)
                .FirstOrDefaultAsync(u => u.Id == userId);
            if (user is null)
                return ServiceResponse<UserAuthResponseDto>.NotFound("Account not found.");

            user.PinEnabled = enabled;
            // Turning the PIN off clears the stored hash so nothing lingers; the client clears its
            // local copy too. Turning it on just re-opens the gate — the user is sent to set a PIN.
            if (!enabled)
                user.AppPinHash = null;

            await _context.SaveChangesAsync();

            _logger.LogInformation("User {UserId} set PinEnabled={Enabled}.", userId, enabled);
            return ServiceResponse<UserAuthResponseDto>.Ok(
                BuildResponse(user), enabled ? "PIN enabled." : "PIN turned off.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to set PinEnabled for user {UserId}.", userId);
            return ServiceResponse<UserAuthResponseDto>.Error("Could not update your PIN setting.");
        }
    }

    public async Task<ServiceResponse<bool>> DeleteAccountAsync(int userId)
    {
        try
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Id == userId);
            if (user is null)
                return ServiceResponse<bool>.NotFound("Account not found.");

            // The Customer -> User FK cascades, so deleting the user also deletes its linked
            // forwarding profile (phone number, destination, bank PIN) in the same operation.
            _context.Users.Remove(user);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Deleted account for user {UserId} (and its linked forwarding profile).", userId);
            return ServiceResponse<bool>.Ok(true, "Your account and all associated data have been deleted.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to delete account for user {UserId}.", userId);
            return ServiceResponse<bool>.Error("Could not delete your account.");
        }
    }
}
