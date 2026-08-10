using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services.Auth;

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
    private readonly ILogger<UserAuthRepository> _logger;

    public UserAuthRepository(
        AppDbContext context,
        IGoogleTokenVerifier googleTokenVerifier,
        IJwtTokenService tokenService,
        IPasswordHasher<User> passwordHasher,
        ILogger<UserAuthRepository> logger)
    {
        _context = context;
        _googleTokenVerifier = googleTokenVerifier;
        _tokenService = tokenService;
        _passwordHasher = passwordHasher;
        _logger = logger;
    }

    public async Task<ServiceResponse<UserAuthResponseDto>> RegisterAsync(RegisterAccountDto dto)
    {
        try
        {
            var fullName = dto.FullName.Trim();
            var email = dto.Email.Trim().ToLowerInvariant();
            var username = dto.Username.Trim();
            var phone = dto.PhoneNumber?.Trim();
            if (string.IsNullOrEmpty(phone)) phone = null;

            if (fullName.Length == 0)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Full name is required.");
            if (username.Length < 3)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Username must be at least 3 characters.");
            if (dto.Password.Length < 6)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Password must be at least 6 characters.");

            var loweredUsername = username.ToLower();
            if (await _context.Users.AnyAsync(u => u.Email != null && u.Email.ToLower() == email))
                return ServiceResponse<UserAuthResponseDto>.Conflict("An account with this email already exists.");
            if (await _context.Users.AnyAsync(u => u.Username != null && u.Username.ToLower() == loweredUsername))
                return ServiceResponse<UserAuthResponseDto>.Conflict("This username is already taken.");
            if (phone is not null && await _context.Customers.AnyAsync(c => c.PhoneNumber == phone))
                return ServiceResponse<UserAuthResponseDto>.Conflict("An account with this phone number already exists.");

            var now = DateTime.UtcNow;
            var user = new User
            {
                FullName = fullName,
                Email = email,
                Username = username,
                CreatedAt = now,
                LastLoginAtUtc = now,
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
                "Registered user {UserId} ({Username}) with linked customer {CustomerId}.",
                user.Id, user.Username, user.Customer!.Id);
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
            var identifier = dto.UsernameOrEmail.Trim();
            if (identifier.Length == 0 || dto.Password.Length == 0)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Username/email and password are required.");

            var lowered = identifier.ToLower();
            var user = await _context.Users
                .Include(u => u.Customer)
                .FirstOrDefaultAsync(u =>
                    (u.Username != null && u.Username.ToLower() == lowered) ||
                    (u.Email != null && u.Email.ToLower() == lowered));

            // Same message for "no such account" and "wrong password" so callers can't probe.
            if (user?.PasswordHash is null)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Incorrect username/email or password.");

            var result = _passwordHasher.VerifyHashedPassword(user, user.PasswordHash, dto.Password);
            if (result == PasswordVerificationResult.Failed)
                return ServiceResponse<UserAuthResponseDto>.BadRequest("Incorrect username/email or password.");

            if (result == PasswordVerificationResult.SuccessRehashNeeded)
                user.PasswordHash = _passwordHasher.HashPassword(user, dto.Password);

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
            FullName = user.FullName,
            ProfilePictureUrl = user.ProfilePictureUrl
        };
    }

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
