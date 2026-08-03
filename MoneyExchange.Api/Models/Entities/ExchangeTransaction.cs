using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A single money-exchange operation: convert <see cref="Amount"/> of
/// <see cref="FromCurrency"/> into <see cref="ToCurrency"/> at <see cref="Rate"/>.
/// </summary>
public class ExchangeTransaction
{
    public int Id { get; set; }

    [Required, MaxLength(120)]
    public string CustomerName { get; set; } = string.Empty;

    /// <summary>ISO-like currency code being sold, e.g. "USD".</summary>
    [Required, MaxLength(3)]
    public string FromCurrency { get; set; } = string.Empty;

    /// <summary>ISO-like currency code being bought, e.g. "SOS".</summary>
    [Required, MaxLength(3)]
    public string ToCurrency { get; set; } = string.Empty;

    /// <summary>Amount expressed in <see cref="FromCurrency"/>.</summary>
    public decimal Amount { get; set; }

    /// <summary>Exchange rate applied (units of ToCurrency per 1 FromCurrency).</summary>
    public decimal Rate { get; set; }

    /// <summary>Result of Amount * Rate, computed by the repository.</summary>
    public decimal ConvertedAmount { get; set; }

    public TransactionStatus Status { get; set; } = TransactionStatus.Pending;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public enum TransactionStatus
{
    Pending = 0,
    Completed = 1,
    Cancelled = 2
}
