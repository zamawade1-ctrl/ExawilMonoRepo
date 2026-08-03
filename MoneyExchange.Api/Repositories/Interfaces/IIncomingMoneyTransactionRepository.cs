using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

/// <summary>Read-only visibility into what the 1-minute auto-forwarding job has processed.</summary>
public interface IIncomingMoneyTransactionRepository
{
    Task<ServiceResponse<List<IncomingMoneyTransaction>>> GetAllAsync();

    Task<ServiceResponse<IncomingMoneyTransaction>> GetByIdAsync(int id);
}
