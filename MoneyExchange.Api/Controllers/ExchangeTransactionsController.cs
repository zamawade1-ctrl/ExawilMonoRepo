using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.DTOs;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

[Route("api/[controller]")]
public class ExchangeTransactionsController : ApiControllerBase
{
    private readonly IExchangeTransactionRepository _repository;

    public ExchangeTransactionsController(IExchangeTransactionRepository repository)
    {
        _repository = repository;
    }

    // GET: api/ExchangeTransactions
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var response = await _repository.GetAllAsync();
        return HandleResponse(response);
    }

    // GET: api/ExchangeTransactions/5
    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var response = await _repository.GetByIdAsync(id);
        return HandleResponse(response);
    }

    // POST: api/ExchangeTransactions
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateExchangeTransactionDto dto)
    {
        var response = await _repository.CreateAsync(dto);
        return HandleResponse(response);
    }

    // PATCH: api/ExchangeTransactions/5/status
    [HttpPatch("{id:int}/status")]
    public async Task<IActionResult> UpdateStatus(int id, [FromBody] UpdateExchangeTransactionStatusDto dto)
    {
        var response = await _repository.UpdateStatusAsync(id, dto);
        return HandleResponse(response);
    }

    // DELETE: api/ExchangeTransactions/5
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var response = await _repository.DeleteAsync(id);
        return HandleResponse(response);
    }
}
