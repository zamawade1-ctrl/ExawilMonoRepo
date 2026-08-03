using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <summary>
/// Holds ALL business + persistence logic for exchange transactions.
/// Controllers call these methods and never talk to the DbContext directly.
/// </summary>
public class ExchangeTransactionRepository : IExchangeTransactionRepository
{
    private readonly AppDbContext _context;
    private readonly ILogger<ExchangeTransactionRepository> _logger;

    public ExchangeTransactionRepository(AppDbContext context, ILogger<ExchangeTransactionRepository> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<ServiceResponse<List<ExchangeTransaction>>> GetAllAsync()
    {
        try
        {
            var items = await _context.ExchangeTransactions
                .AsNoTracking()
                .OrderByDescending(t => t.CreatedAt)
                .ToListAsync();

            return ServiceResponse<List<ExchangeTransaction>>.Ok(
                items, $"Retrieved {items.Count} transaction(s).");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve exchange transactions.");
            return ServiceResponse<List<ExchangeTransaction>>.Error(
                "Could not retrieve transactions.");
        }
    }

    public async Task<ServiceResponse<ExchangeTransaction>> GetByIdAsync(int id)
    {
        try
        {
            if (id <= 0)
                return ServiceResponse<ExchangeTransaction>.BadRequest("Id must be a positive number.");

            var item = await _context.ExchangeTransactions
                .AsNoTracking()
                .FirstOrDefaultAsync(t => t.Id == id);

            return item is null
                ? ServiceResponse<ExchangeTransaction>.NotFound($"Transaction {id} was not found.")
                : ServiceResponse<ExchangeTransaction>.Ok(item, "Transaction retrieved.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve transaction {Id}.", id);
            return ServiceResponse<ExchangeTransaction>.Error("Could not retrieve the transaction.");
        }
    }

    public async Task<ServiceResponse<ExchangeTransaction>> CreateAsync(CreateExchangeTransactionDto dto)
    {
        try
        {
            // ---- Business validation lives here, in the repository ----
            var from = dto.FromCurrency?.Trim().ToUpperInvariant() ?? string.Empty;
            var to = dto.ToCurrency?.Trim().ToUpperInvariant() ?? string.Empty;

            if (from.Length != 3 || to.Length != 3)
                return ServiceResponse<ExchangeTransaction>.BadRequest(
                    "Currency codes must be exactly 3 letters.");

            if (from == to)
                return ServiceResponse<ExchangeTransaction>.BadRequest(
                    "From and To currencies must be different.");

            if (dto.Amount <= 0)
                return ServiceResponse<ExchangeTransaction>.BadRequest("Amount must be greater than zero.");

            if (dto.Rate <= 0)
                return ServiceResponse<ExchangeTransaction>.BadRequest("Rate must be greater than zero.");

            var entity = new ExchangeTransaction
            {
                CustomerName = dto.CustomerName.Trim(),
                FromCurrency = from,
                ToCurrency = to,
                Amount = dto.Amount,
                Rate = dto.Rate,
                ConvertedAmount = decimal.Round(dto.Amount * dto.Rate, 2),
                Status = TransactionStatus.Pending,
                CreatedAt = DateTime.UtcNow
            };

            await _context.ExchangeTransactions.AddAsync(entity);
            await _context.SaveChangesAsync();

            return ServiceResponse<ExchangeTransaction>.CreatedResult(
                entity, "Exchange transaction created.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create exchange transaction.");
            return ServiceResponse<ExchangeTransaction>.Error("Could not create the transaction.");
        }
    }

    public async Task<ServiceResponse<ExchangeTransaction>> UpdateStatusAsync(
        int id, UpdateExchangeTransactionStatusDto dto)
    {
        try
        {
            if (id <= 0)
                return ServiceResponse<ExchangeTransaction>.BadRequest("Id must be a positive number.");

            var entity = await _context.ExchangeTransactions.FirstOrDefaultAsync(t => t.Id == id);
            if (entity is null)
                return ServiceResponse<ExchangeTransaction>.NotFound($"Transaction {id} was not found.");

            // ---- State-transition rules live here ----
            if (entity.Status == TransactionStatus.Completed)
                return ServiceResponse<ExchangeTransaction>.Conflict(
                    "A completed transaction can no longer change status.");

            if (entity.Status == TransactionStatus.Cancelled)
                return ServiceResponse<ExchangeTransaction>.Conflict(
                    "A cancelled transaction can no longer change status.");

            entity.Status = dto.Status;
            await _context.SaveChangesAsync();

            return ServiceResponse<ExchangeTransaction>.Ok(
                entity, $"Transaction status updated to {dto.Status}.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to update status for transaction {Id}.", id);
            return ServiceResponse<ExchangeTransaction>.Error("Could not update the transaction status.");
        }
    }

    public async Task<ServiceResponse<bool>> DeleteAsync(int id)
    {
        try
        {
            if (id <= 0)
                return ServiceResponse<bool>.BadRequest("Id must be a positive number.");

            var entity = await _context.ExchangeTransactions.FirstOrDefaultAsync(t => t.Id == id);
            if (entity is null)
                return ServiceResponse<bool>.NotFound($"Transaction {id} was not found.");

            _context.ExchangeTransactions.Remove(entity);
            await _context.SaveChangesAsync();

            return ServiceResponse<bool>.Ok(true, $"Transaction {id} deleted.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to delete transaction {Id}.", id);
            return ServiceResponse<bool>.Error("Could not delete the transaction.");
        }
    }
}
