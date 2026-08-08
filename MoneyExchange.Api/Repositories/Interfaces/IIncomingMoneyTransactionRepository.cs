using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

/// <summary>
/// Read-only visibility into what the 1-minute auto-forwarding job has processed, scoped to
/// the signed-in user's own forwarding profile - a user must never see another user's
/// transactions.
/// </summary>
public interface IIncomingMoneyTransactionRepository
{
    Task<ServiceResponse<List<IncomingMoneyTransaction>>> GetAllForUserAsync(int userId);

    Task<ServiceResponse<IncomingMoneyTransaction>> GetByIdForUserAsync(int userId, int id);
}
