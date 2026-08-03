using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs;

/// <summary>Payload for creating a new exchange transaction.</summary>
public class CreateExchangeTransactionDto
{
    [Required, MaxLength(120)]
    public string CustomerName { get; set; } = string.Empty;

    [Required, MaxLength(3), MinLength(3)]
    public string FromCurrency { get; set; } = string.Empty;

    [Required, MaxLength(3), MinLength(3)]
    public string ToCurrency { get; set; } = string.Empty;

    [Range(0.01, double.MaxValue, ErrorMessage = "Amount must be greater than zero.")]
    public decimal Amount { get; set; }

    [Range(0.000001, double.MaxValue, ErrorMessage = "Rate must be greater than zero.")]
    public decimal Rate { get; set; }
}
