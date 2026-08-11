using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Services.Forwarding;

/// <summary>
/// Which rail a received USD amount should be pushed out on. The concrete
/// destination (mobile number / bank account) and PINs are NOT stored server-side
/// — they live only on the device — so this server-side fallback carries the
/// method alone.
/// </summary>
public record ForwardDestination(ForwardingMethod Method);

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
