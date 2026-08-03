using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.Forwarding;

/// <summary>Where a received USD amount should be pushed: a mobile number (via USSD) or a bank account.</summary>
public record ForwardDestination(
    ForwardingMethod Method,
    string? PhoneNumber,
    string? BankName,
    string? BankAccountNumber,
    string? BankAccountHolderName);

public record ForwardResult(bool Success, string Note);

/// <summary>
/// Pushes a received USD amount out to a customer's chosen destination. The
/// real USSD gateway / bank-transfer integration will replace this stub.
/// </summary>
public interface IMoneyForwardingService
{
    Task<ForwardResult> ForwardAsync(
        ForwardDestination destination, decimal amountUsd, CancellationToken cancellationToken = default);
}
