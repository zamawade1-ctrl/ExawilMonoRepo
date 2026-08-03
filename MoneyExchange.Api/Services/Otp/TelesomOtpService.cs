namespace MoneyExchange.Api.Services.Otp;

/// <summary>
/// Placeholder Telesom implementation. Logs the OTP instead of sending an SMS
/// until the real Telesom API endpoint/credentials are available. Swap this
/// registration in Program.cs for the real implementation when it's ready.
/// </summary>
public class TelesomOtpService : ITelesomOtpService
{
    private readonly ILogger<TelesomOtpService> _logger;

    public TelesomOtpService(ILogger<TelesomOtpService> logger)
    {
        _logger = logger;
    }

    public Task SendOtpAsync(string phoneNumber, string code, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "[Telesom OTP stub] Would send code {Code} to {PhoneNumber} via the Telesom SMS API.",
            code, phoneNumber);
        return Task.CompletedTask;
    }
}
