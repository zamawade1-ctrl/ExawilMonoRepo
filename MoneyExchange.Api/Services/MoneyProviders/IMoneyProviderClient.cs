using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.MoneyProviders;

/// <summary>A USD receipt reported by an external mobile-money provider (Zaad, eDahab).</summary>
public record IncomingPaymentDto(
    string ProviderTransactionId,
    string SenderPhoneNumber,
    decimal AmountUsd,
    DateTime ReceivedAtUtc);

/// <summary>
/// Client for polling a mobile-money provider for newly received USD payments.
/// The stub implementations return no receipts; real HTTP calls to each
/// provider's API will replace them once credentials/API docs are available.
/// </summary>
public interface IMoneyProviderClient
{
    MoneyProvider Provider { get; }

    Task<IReadOnlyList<IncomingPaymentDto>> GetLatestUsdReceiptsAsync(
        DateTime sinceUtc, CancellationToken cancellationToken = default);
}
