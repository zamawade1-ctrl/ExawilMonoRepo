using MoneyExchange.Api.Models.DTOs;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

/// <summary>
/// Contract for the exchange-transaction data/business layer. Every method
/// returns a <see cref="ServiceResponse{T}"/> so the controller can map the
/// logical status onto an HTTP status code without any business logic of its own.
/// </summary>
public interface IExchangeTransactionRepository
{
    Task<ServiceResponse<List<ExchangeTransaction>>> GetAllAsync();

    Task<ServiceResponse<ExchangeTransaction>> GetByIdAsync(int id);

    Task<ServiceResponse<ExchangeTransaction>> CreateAsync(CreateExchangeTransactionDto dto);

    Task<ServiceResponse<ExchangeTransaction>> UpdateStatusAsync(int id, UpdateExchangeTransactionStatusDto dto);

    Task<ServiceResponse<bool>> DeleteAsync(int id);
}
