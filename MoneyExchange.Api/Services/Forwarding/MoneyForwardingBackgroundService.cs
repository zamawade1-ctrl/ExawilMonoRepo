using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Services.MoneyProviders;

namespace MoneyExchange.Api.Services.Forwarding;

/// <summary>
/// Every minute: pulls newly-received USD payments from Zaad and eDahab,
/// matches each one to a verified customer by phone number, and forwards the
/// amount to that customer's chosen destination (mobile number via USSD, or
/// bank account).
/// </summary>
public class MoneyForwardingBackgroundService : BackgroundService
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromMinutes(1);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<MoneyForwardingBackgroundService> _logger;

    private DateTime _lastPolledAtUtc = DateTime.UtcNow.Add(-PollInterval);

    public MoneyForwardingBackgroundService(
        IServiceScopeFactory scopeFactory, ILogger<MoneyForwardingBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(PollInterval);

        do
        {
            var cycleStartedAtUtc = DateTime.UtcNow;

            try
            {
                await RunCycleAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Money forwarding cycle failed.");
            }

            _lastPolledAtUtc = cycleStartedAtUtc;
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    private async Task RunCycleAsync(CancellationToken cancellationToken)
    {
        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var providerClients = scope.ServiceProvider.GetServices<IMoneyProviderClient>();
        var forwardingService = scope.ServiceProvider.GetRequiredService<IMoneyForwardingService>();

        var processedAny = false;

        foreach (var providerClient in providerClients)
        {
            var receipts = await providerClient.GetLatestUsdReceiptsAsync(_lastPolledAtUtc, cancellationToken);

            foreach (var receipt in receipts)
            {
                var alreadyProcessed = await context.IncomingMoneyTransactions.AnyAsync(
                    t => t.Provider == providerClient.Provider && t.ProviderTransactionId == receipt.ProviderTransactionId,
                    cancellationToken);

                if (alreadyProcessed)
                    continue;

                processedAny = true;

                var transaction = new IncomingMoneyTransaction
                {
                    Provider = providerClient.Provider,
                    ProviderTransactionId = receipt.ProviderTransactionId,
                    SenderPhoneNumber = receipt.SenderPhoneNumber,
                    AmountUsd = receipt.AmountUsd,
                    ReceivedAt = receipt.ReceivedAtUtc,
                    CreatedAt = DateTime.UtcNow
                };

                var customer = await context.Customers.FirstOrDefaultAsync(
                    c => c.PhoneNumber == receipt.SenderPhoneNumber, cancellationToken);

                if (customer is null)
                {
                    transaction.ForwardStatus = ForwardStatus.Unmatched;
                    transaction.ForwardNote = "No customer is registered with this phone number.";
                }
                else if (!customer.IsVerified)
                {
                    transaction.CustomerId = customer.Id;
                    transaction.ForwardStatus = ForwardStatus.Unmatched;
                    transaction.ForwardNote = "Customer has not completed Telesom OTP verification.";
                }
                else
                {
                    transaction.CustomerId = customer.Id;

                    var destination = new ForwardDestination(customer.ForwardingMethod);

                    var result = await forwardingService.ForwardAsync(destination, receipt.AmountUsd, cancellationToken);

                    transaction.ForwardStatus = result.Success ? ForwardStatus.Forwarded : ForwardStatus.Failed;
                    transaction.ForwardNote = result.Note;
                    transaction.ForwardedAt = result.Success ? DateTime.UtcNow : null;
                }

                await context.IncomingMoneyTransactions.AddAsync(transaction, cancellationToken);
            }
        }

        if (processedAny)
            await context.SaveChangesAsync(cancellationToken);
    }
}
