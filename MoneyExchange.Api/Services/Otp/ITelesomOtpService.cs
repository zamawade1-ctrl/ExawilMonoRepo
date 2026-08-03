namespace MoneyExchange.Api.Services.Otp;

/// <summary>
/// Delivers a one-time password to a phone number via Telesom. The real
/// Telesom API integration will be plugged in here later; for now the
/// registered implementation is a stub.
/// </summary>
public interface ITelesomOtpService
{
    Task SendOtpAsync(string phoneNumber, string code, CancellationToken cancellationToken = default);
}
