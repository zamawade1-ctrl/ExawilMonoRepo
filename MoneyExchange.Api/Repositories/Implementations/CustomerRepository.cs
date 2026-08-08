using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// Holds the registration ("the form") business logic: a customer's identity
/// and where auto-forwarded USD should be sent.
/// </summary>
public class CustomerRepository : ICustomerRepository
{
    private readonly AppDbContext _context;
    private readonly ILogger<CustomerRepository> _logger;

    public CustomerRepository(AppDbContext context, ILogger<CustomerRepository> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<ServiceResponse<List<Customer>>> GetAllAsync()
    {
        try
        {
            var items = await _context.Customers
                .AsNoTracking()
                .OrderByDescending(c => c.CreatedAt)
                .ToListAsync();

            return ServiceResponse<List<Customer>>.Ok(items, $"Retrieved {items.Count} customer(s).");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve customers.");
            return ServiceResponse<List<Customer>>.Error("Could not retrieve customers.");
        }
    }

    public async Task<ServiceResponse<Customer>> GetByIdAsync(int id)
    {
        try
        {
            if (id <= 0)
                return ServiceResponse<Customer>.BadRequest("Id must be a positive number.");

            var item = await _context.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == id);

            return item is null
                ? ServiceResponse<Customer>.NotFound($"Customer {id} was not found.")
                : ServiceResponse<Customer>.Ok(item, "Customer retrieved.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve customer {Id}.", id);
            return ServiceResponse<Customer>.Error("Could not retrieve the customer.");
        }
    }

    public async Task<ServiceResponse<Customer>> RegisterAsync(RegisterCustomerDto dto)
    {
        try
        {
            var validationError = ValidateForwardingFields(dto);
            if (validationError is not null)
                return ServiceResponse<Customer>.BadRequest(validationError);

            var phone = dto.PhoneNumber?.Trim() ?? string.Empty;

            // Phone is optional now; only enforce uniqueness when one was supplied.
            if (phone.Length > 0)
            {
                var exists = await _context.Customers.AnyAsync(c => c.PhoneNumber == phone);
                if (exists)
                    return ServiceResponse<Customer>.Conflict("A customer with this phone number is already registered.");
            }

            var entity = new Customer
            {
                // OTP verification is bypassed for now (Telesom API isn't available yet) - see
                // MoneyExchange.Api/Services/Otp/ITelesomOtpService.cs. Customers are treated as
                // verified immediately so auto-forwarding works without an OTP round trip.
                IsVerified = true,
                CreatedAt = DateTime.UtcNow
            };
            ApplyFields(entity, dto, phone);

            await _context.Customers.AddAsync(entity);
            await _context.SaveChangesAsync();

            return ServiceResponse<Customer>.CreatedResult(
                entity, "Customer registered. Auto-forwarding is active.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register customer.");
            return ServiceResponse<Customer>.Error("Could not register the customer.");
        }
    }

    public async Task<ServiceResponse<Customer>> GetByUserIdAsync(int userId)
    {
        try
        {
            var item = await _context.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.UserId == userId);

            return item is null
                ? ServiceResponse<Customer>.NotFound("No forwarding profile has been set up yet.")
                : ServiceResponse<Customer>.Ok(item, "Forwarding profile retrieved.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve forwarding profile for user {UserId}.", userId);
            return ServiceResponse<Customer>.Error("Could not retrieve the forwarding profile.");
        }
    }

    public async Task<ServiceResponse<Customer>> UpsertForUserAsync(int userId, RegisterCustomerDto dto)
    {
        try
        {
            var validationError = ValidateForwardingFields(dto);
            if (validationError is not null)
                return ServiceResponse<Customer>.BadRequest(validationError);

            var phone = dto.PhoneNumber?.Trim() ?? string.Empty;
            var entity = await _context.Customers.FirstOrDefaultAsync(c => c.UserId == userId);

            // Phone is optional now; only enforce uniqueness when one was supplied.
            if (phone.Length > 0)
            {
                var phoneTakenByAnotherProfile = await _context.Customers
                    .AnyAsync(c => c.PhoneNumber == phone && c.Id != (entity != null ? entity.Id : 0));
                if (phoneTakenByAnotherProfile)
                    return ServiceResponse<Customer>.Conflict("This phone number is already registered to another profile.");
            }

            var isNew = entity is null;
            if (isNew)
            {
                entity = new Customer
                {
                    UserId = userId,
                    IsVerified = true,
                    CreatedAt = DateTime.UtcNow
                };
            }

            ApplyFields(entity!, dto, phone);

            if (isNew)
                await _context.Customers.AddAsync(entity!);

            await _context.SaveChangesAsync();

            return ServiceResponse<Customer>.Ok(entity!, "Forwarding profile saved.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save forwarding profile for user {UserId}.", userId);
            return ServiceResponse<Customer>.Error("Could not save the forwarding profile.");
        }
    }

    private static string? ValidateForwardingFields(RegisterCustomerDto dto)
    {
        if (dto.ForwardingMethod == ForwardingMethod.MobileNumber &&
            string.IsNullOrWhiteSpace(dto.ForwardingPhoneNumber))
            return "ForwardingPhoneNumber is required when ForwardingMethod is MobileNumber.";

        // Bank forwarding collapsed to a single PIN, carried in BankAccountNumber
        // (the old bank name / holder fields are no longer collected by the app).
        if (dto.ForwardingMethod == ForwardingMethod.BankAccount &&
            string.IsNullOrWhiteSpace(dto.BankAccountNumber))
            return "Bank account PIN is required when ForwardingMethod is BankAccount.";

        return null;
    }

    private static void ApplyFields(Customer entity, RegisterCustomerDto dto, string phone)
    {
        entity.FullName = dto.FullName.Trim();
        // Store null (not "") when no phone was supplied, so phone-less profiles
        // don't collide on the unique PhoneNumber index (NULLs are distinct).
        entity.PhoneNumber = phone.Length == 0 ? null : phone;
        entity.ForwardingMethod = dto.ForwardingMethod;
        entity.ForwardingPhoneNumber = dto.ForwardingMethod == ForwardingMethod.MobileNumber
            ? dto.ForwardingPhoneNumber!.Trim()
            : null;
        // Bank forwarding is a single PIN now, stored in BankAccountNumber. The
        // old bank name / holder columns are no longer collected - keep them null.
        // (Null-tolerant .Trim() in case a legacy caller still sends them.)
        entity.BankName = null;
        entity.BankAccountNumber = dto.ForwardingMethod == ForwardingMethod.BankAccount
            ? dto.BankAccountNumber?.Trim()
            : null;
        entity.BankAccountHolderName = null;
    }
}
