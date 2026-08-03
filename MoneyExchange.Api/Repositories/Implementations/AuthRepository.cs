using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services.Auth;
using MoneyExchange.Api.Services.Otp;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// Drives the Telesom OTP login flow: request a code, verify it, issue a JWT.
/// Actual SMS delivery is delegated to <see cref="ITelesomOtpService"/>, which
/// is a stub pending the real Telesom API integration.
/// </summary>
public class AuthRepository : IAuthRepository
{
    private static readonly Random Rng = new();

    private readonly AppDbContext _context;
    private readonly ITelesomOtpService _otpService;
    private readonly IJwtTokenService _tokenService;
    private readonly ILogger<AuthRepository> _logger;

    public AuthRepository(
        AppDbContext context,
        ITelesomOtpService otpService,
        IJwtTokenService tokenService,
        ILogger<AuthRepository> logger)
    {
        _context = context;
        _otpService = otpService;
        _tokenService = tokenService;
        _logger = logger;
    }

    public async Task<ServiceResponse<bool>> RequestOtpAsync(RequestOtpDto dto)
    {
        try
        {
            var phone = dto.PhoneNumber.Trim();
            if (phone.Length == 0)
                return ServiceResponse<bool>.BadRequest("Phone number is required.");

            var customerExists = await _context.Customers.AnyAsync(c => c.PhoneNumber == phone);
            if (!customerExists)
                return ServiceResponse<bool>.NotFound("No customer is registered with this phone number.");

            var code = Rng.Next(0, 1_000_000).ToString("D6");

            var otp = new OtpVerification
            {
                PhoneNumber = phone,
                Code = code,
                ExpiresAt = DateTime.UtcNow.AddMinutes(5),
                IsUsed = false,
                CreatedAt = DateTime.UtcNow
            };

            await _context.OtpVerifications.AddAsync(otp);
            await _context.SaveChangesAsync();

            await _otpService.SendOtpAsync(phone, code);

            return ServiceResponse<bool>.Ok(true, "OTP sent.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to request OTP.");
            return ServiceResponse<bool>.Error("Could not send the OTP.");
        }
    }

    public async Task<ServiceResponse<AuthResponseDto>> VerifyOtpAsync(VerifyOtpDto dto)
    {
        try
        {
            var phone = dto.PhoneNumber.Trim();
            var code = dto.Code.Trim();

            var otp = await _context.OtpVerifications
                .Where(o => o.PhoneNumber == phone && o.Code == code && !o.IsUsed)
                .OrderByDescending(o => o.CreatedAt)
                .FirstOrDefaultAsync();

            if (otp is null)
                return ServiceResponse<AuthResponseDto>.BadRequest("Invalid OTP code.");

            if (otp.ExpiresAt < DateTime.UtcNow)
                return ServiceResponse<AuthResponseDto>.BadRequest("OTP code has expired.");

            var customer = await _context.Customers.FirstOrDefaultAsync(c => c.PhoneNumber == phone);
            if (customer is null)
                return ServiceResponse<AuthResponseDto>.NotFound("No customer is registered with this phone number.");

            otp.IsUsed = true;
            customer.IsVerified = true;
            await _context.SaveChangesAsync();

            var token = _tokenService.CreateToken(customer);

            var response = new AuthResponseDto
            {
                AccessToken = token.AccessToken,
                ExpiresAtUtc = token.ExpiresAtUtc,
                CustomerId = customer.Id,
                FullName = customer.FullName,
                PhoneNumber = customer.PhoneNumber
            };

            return ServiceResponse<AuthResponseDto>.Ok(response, "OTP verified.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to verify OTP.");
            return ServiceResponse<AuthResponseDto>.Error("Could not verify the OTP.");
        }
    }
}
