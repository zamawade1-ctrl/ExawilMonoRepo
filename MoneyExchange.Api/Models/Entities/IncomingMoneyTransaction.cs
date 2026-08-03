using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>A USD receipt pulled from Zaad or eDahab, and its downstream auto-forwarding outcome.</summary>
public class IncomingMoneyTransaction
{
    public int Id { get; set; }

    public MoneyProvider Provider { get; set; }

    /// <summary>The provider's own transaction reference, used to de-duplicate polls.</summary>
    [Required, MaxLength(80)]
    public string ProviderTransactionId { get; set; } = string.Empty;

    [Required, MaxLength(20)]
    public string SenderPhoneNumber { get; set; } = string.Empty;

    public decimal AmountUsd { get; set; }

    public int? CustomerId { get; set; }
    public Customer? Customer { get; set; }

    public ForwardStatus ForwardStatus { get; set; } = ForwardStatus.Pending;

    [MaxLength(300)]
    public string? ForwardNote { get; set; }

    public DateTime ReceivedAt { get; set; }

    public DateTime? ForwardedAt { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public enum MoneyProvider
{
    Zaad = 0,
    EDahab = 1
}

public enum ForwardStatus
{
    Pending = 0,
    Forwarded = 1,
    Failed = 2,
    Unmatched = 3
}