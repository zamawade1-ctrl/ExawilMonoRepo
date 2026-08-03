using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

/// <summary>Read-only visibility into the USD receipts the 1-minute auto-forwarding job has processed.</summary>
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
        var response = await _repository.GetAllAsync();
        return HandleResponse(response);
    }

    // GET: api/IncomingMoneyTransactions/5
    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var response = await _repository.GetByIdAsync(id);
        return HandleResponse(response);
    }
}
