using System.ComponentModel.DataAnnotations;
using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Models.DTOs;

/// <summary>Payload for transitioning a transaction to a new status.</summary>
public class UpdateExchangeTransactionStatusDto
{
    [Required]
    [EnumDataType(typeof(TransactionStatus))]
    public TransactionStatus Status { get; set; }
}
