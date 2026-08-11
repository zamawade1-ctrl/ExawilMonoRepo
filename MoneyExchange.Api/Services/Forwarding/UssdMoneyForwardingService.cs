using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.Forwarding;

/// <summary>
/// Placeholder forwarding implementation. Logs what it would do instead of
/// dialing a USSD session or initiating a bank transfer, until the real
/// gateway integrations are available.
/// </summary>
public class UssdMoneyForwardingService : IMoneyForwardingService
{
    private readonly ILogger<UssdMoneyForwardingService> _logger;

    public UssdMoneyForwardingService(ILogger<UssdMoneyForwardingService> logger)
    {
        _logger = logger;
    }

    public Task<ForwardResult> ForwardAsync(
        ForwardDestination destination, decimal amountUsd, CancellationToken cancellationToken = default)
    {
        // The concrete destination + PIN aren't stored server-side (device-only), so
        // this fallback can only note the method — real forwarding runs on-device.
        var note = destination.Method switch
        {
            ForwardingMethod.MobileNumber =>
                $"[USSD stub] Would forward ${amountUsd:F2} to the customer's mobile number (destination stored on-device).",
            ForwardingMethod.BankAccount =>
                $"[Bank stub] Would transfer ${amountUsd:F2} to the customer's bank account (destination stored on-device).",
            _ => "Unknown forwarding method."
        };

        _logger.LogInformation("{Note}", note);
        return Task.FromResult(new ForwardResult(true, note));
    }
}
