using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

public interface ICustomerRepository
{
    Task<ServiceResponse<List<Customer>>> GetAllAsync();

    Task<ServiceResponse<Customer>> GetByIdAsync(int id);

    Task<ServiceResponse<Customer>> RegisterAsync(RegisterCustomerDto dto);
}
