using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

public interface ICustomerRepository
{
    Task<ServiceResponse<List<Customer>>> GetAllAsync();

    Task<ServiceResponse<Customer>> GetByIdAsync(int id);

    Task<ServiceResponse<Customer>> RegisterAsync(RegisterCustomerDto dto);

    /// <summary>The signed-in user's own forwarding profile, if they've set one up.</summary>
    Task<ServiceResponse<Customer>> GetByUserIdAsync(int userId);

    /// <summary>Creates or updates the signed-in user's forwarding profile.</summary>
    Task<ServiceResponse<Customer>> UpsertForUserAsync(int userId, RegisterCustomerDto dto);
}
