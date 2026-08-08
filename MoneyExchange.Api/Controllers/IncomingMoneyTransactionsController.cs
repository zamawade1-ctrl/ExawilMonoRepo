using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

/// <summary>
/// Read-only visibility into the USD receipts the 1-minute auto-forwarding job has processed,
/// scoped to the signed-in user's own forwarding profile.
/// </summary>
[Authorize]
[Route("api/[controller]")]
public class IncomingMoneyTransactionsController : ApiControllerBase
{
    private readonly IIncomingMoneyTransactionRepository _repository;

    public IncomingMoneyTransactionsController(IIncomingMoneyTransactionRepository repository)
    {
        _repository = repository;
    }

    // GET: api/IncomingMoneyTransactions
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        if (!TryGetAuthenticatedUserId(out var userId))
            return Forbid();

        var response = await _repository.GetAllForUserAsync(userId);
        return HandleResponse(response);
    }

    // GET: api/IncomingMoneyTransactions/5
    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        if (!TryGetAuthenticatedUserId(out var userId))
            return Forbid();

        var response = await _repository.GetByIdForUserAsync(userId, id);
        return HandleResponse(response);
    }
}
