using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.MoneyProviders;

/// <summary>
/// Placeholder Zaad integration. Returns no receipts until the real Zaad API
/// endpoint/credentials are wired in.
/// </summary>
public class ZaadMoneyProviderClient : IMoneyProviderClient
{
    private readonly ILogger<ZaadMoneyProviderClient> _logger;

    public ZaadMoneyProviderClient(ILogger<ZaadMoneyProviderClient> logger)
    {
        _logger = logger;
    }

    public MoneyProvider Provider => MoneyProvider.Zaad;

    public Task<IReadOnlyList<IncomingPaymentDto>> GetLatestUsdReceiptsAsync(
        DateTime sinceUtc, CancellationToken cancellationToken = default)
    {
        _logger.LogDebug("[Zaad stub] Would fetch USD receipts received since {SinceUtc:o}.", sinceUtc);
        return Task.FromResult<IReadOnlyList<IncomingPaymentDto>>(Array.Empty<IncomingPaymentDto>());
    }
}
