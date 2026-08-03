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
            var phone = dto.PhoneNumber.Trim();
            if (phone.Length == 0)
                return ServiceResponse<Customer>.BadRequest("Phone number is required.");

            if (dto.ForwardingMethod == ForwardingMethod.MobileNumber &&
                string.IsNullOrWhiteSpace(dto.ForwardingPhoneNumber))
                return ServiceResponse<Customer>.BadRequest(
                    "ForwardingPhoneNumber is required when ForwardingMethod is MobileNumber.");

            if (dto.ForwardingMethod == ForwardingMethod.BankAccount &&
                (string.IsNullOrWhiteSpace(dto.BankName) ||
                 string.IsNullOrWhiteSpace(dto.BankAccountNumber) ||
                 string.IsNullOrWhiteSpace(dto.BankAccountHolderName)))
                return ServiceResponse<Customer>.BadRequest(
                    "BankName, BankAccountNumber and BankAccountHolderName are required when ForwardingMethod is BankAccount.");

            var exists = await _context.Customers.AnyAsync(c => c.PhoneNumber == phone);
            if (exists)
                return ServiceResponse<Customer>.Conflict("A customer with this phone number is already registered.");

            var entity = new Customer
            {
                FullName = dto.FullName.Trim(),
                PhoneNumber = phone,
                ForwardingMethod = dto.ForwardingMethod,
                ForwardingPhoneNumber = dto.ForwardingMethod == ForwardingMethod.MobileNumber
                    ? dto.ForwardingPhoneNumber!.Trim()
                    : null,
                BankName = dto.ForwardingMethod == ForwardingMethod.BankAccount ? dto.BankName!.Trim() : null,
                BankAccountNumber = dto.ForwardingMethod == ForwardingMethod.BankAccount
                    ? dto.BankAccountNumber!.Trim()
                    : null,
                BankAccountHolderName = dto.ForwardingMethod == ForwardingMethod.BankAccount
                    ? dto.BankAccountHolderName!.Trim()
                    : null,
                // OTP verification is bypassed for now (Telesom API isn't available yet) - see
                // MoneyExchange.Api/Services/Otp/ITelesomOtpService.cs. Customers are treated as
                // verified immediately so auto-forwarding works without an OTP round trip.
                IsVerified = true,
                CreatedAt = DateTime.UtcNow
            };

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
}
