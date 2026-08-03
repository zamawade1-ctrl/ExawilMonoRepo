using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services.Auth;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// Verifies a Google ID token, upserts the matching <see cref="User"/>, and issues a JWT.
/// No hosted auth provider (e.g. Supabase Auth) is involved - the token is verified directly
/// against Google's public keys via <see cref="IGoogleTokenVerifier"/>.
/// </summary>
public class UserAuthRepository : IUserAuthRepository
{
    private readonly AppDbContext _context;
    private readonly IGoogleTokenVerifier _googleTokenVerifier;
    private readonly IJwtTokenService _tokenService;
    private readonly ILogger<UserAuthRepository> _logger;

    public UserAuthRepository(
        AppDbContext context,
        IGoogleTokenVerifier googleTokenVerifier,
        IJwtTokenService tokenService,
        ILogger<UserAuthRepository> logger)
    {
        _context = context;
        _googleTokenVerifier = googleTokenVerifier;
        _tokenService = tokenService;
        _logger = logger;
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

            var token = _tokenService.CreateToken(user);

            var response = new UserAuthResponseDto
            {
                AccessToken = token.AccessToken,
                ExpiresAtUtc = token.ExpiresAtUtc,
                UserId = user.Id,
                Email = user.Email,
                FullName = user.FullName,
                ProfilePictureUrl = user.ProfilePictureUrl
            };

            return ServiceResponse<UserAuthResponseDto>.Ok(response, "Signed in with Google.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to complete Google sign-in.");
            return ServiceResponse<UserAuthResponseDto>.Error("Could not complete Google sign-in.");
        }
    }
}
