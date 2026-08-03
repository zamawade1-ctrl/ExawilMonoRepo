using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.MoneyProviders;

/// <summary>
/// Placeholder eDahab integration. Returns no receipts until the real eDahab
/// API endpoint/credentials are wired in.
/// </summary>
public class EDahabMoneyProviderClient : IMoneyProviderClient
{
    private readonly ILogger<EDahabMoneyProviderClient> _logger;

    public EDahabMoneyProviderClient(ILogger<EDahabMoneyProviderClient> logger)
    {
        _logger = logger;
    }

    public MoneyProvider Provider => MoneyProvider.EDahab;

    public Task<IReadOnlyList<IncomingPaymentDto>> GetLatestUsdReceiptsAsync(
        DateTime sinceUtc, CancellationToken cancellationToken = default)
    {
        _logger.LogDebug("[eDahab stub] Would fetch USD receipts received since {SinceUtc:o}.", sinceUtc);
        return Task.FromResult<IReadOnlyList<IncomingPaymentDto>>(Array.Empty<IncomingPaymentDto>());
    }
}
