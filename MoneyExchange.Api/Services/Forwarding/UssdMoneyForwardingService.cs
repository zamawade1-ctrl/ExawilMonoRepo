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
        var note = destination.Method switch
        {
            ForwardingMethod.MobileNumber =>
                $"[USSD stub] Would forward ${amountUsd:F2} to mobile number {destination.PhoneNumber}.",
            ForwardingMethod.BankAccount =>
                $"[Bank stub] Would transfer ${amountUsd:F2} to {destination.BankAccountHolderName} " +
                $"at {destination.BankName} (acct {destination.BankAccountNumber}).",
            _ => "Unknown forwarding method."
        };

        _logger.LogInformation("{Note}", note);
        return Task.FromResult(new ForwardResult(true, note));
    }
}
