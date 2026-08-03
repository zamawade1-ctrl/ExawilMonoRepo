using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Repositories.Implementations;

public class IncomingMoneyTransactionRepository : IIncomingMoneyTransactionRepository
{
    private readonly AppDbContext _context;
    private readonly ILogger<IncomingMoneyTransactionRepository> _logger;

    public IncomingMoneyTransactionRepository(AppDbContext context, ILogger<IncomingMoneyTransactionRepository> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<ServiceResponse<List<IncomingMoneyTransaction>>> GetAllAsync()
    {
        try
        {
            var items = await _context.IncomingMoneyTransactions
                .AsNoTracking()
                .Include(t => t.Customer)
                .OrderByDescending(t => t.CreatedAt)
                .ToListAsync();

            return ServiceResponse<List<IncomingMoneyTransaction>>.Ok(
                items, $"Retrieved {items.Count} incoming transaction(s).");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve incoming money transactions.");
            return ServiceResponse<List<IncomingMoneyTransaction>>.Error("Could not retrieve incoming transactions.");
        }
    }

    public async Task<ServiceResponse<IncomingMoneyTransaction>> GetByIdAsync(int id)
    {
        try
        {
            if (id <= 0)
                return ServiceResponse<IncomingMoneyTransaction>.BadRequest("Id must be a positive number.");

            var item = await _context.IncomingMoneyTransactions
                .AsNoTracking()
                .Include(t => t.Customer)
                .FirstOrDefaultAsync(t => t.Id == id);

            return item is null
                ? ServiceResponse<IncomingMoneyTransaction>.NotFound($"Incoming transaction {id} was not found.")
                : ServiceResponse<IncomingMoneyTransaction>.Ok(item, "Incoming transaction retrieved.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve incoming transaction {Id}.", id);
            return ServiceResponse<IncomingMoneyTransaction>.Error("Could not retrieve the incoming transaction.");
        }
    }
}
