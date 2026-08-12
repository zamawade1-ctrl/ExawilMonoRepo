namespace MoneyExchange.Api.Services.Otp;

/// <summary>
/// Config for OTP issuance + throttling, bound from the <c>Otp</c> section of configuration.
/// </summary>
public class OtpOptions
{
    public const string SectionName = "Otp";

    /// <summary>How long an issued code stays valid, in minutes.</summary>
    public int CodeLifetimeMinutes { get; set; } = 5;

    /// <summary>
    /// Minimum gap between two OTP requests for the same phone, in seconds. The app's "request new
    /// code" button re-activates after this window (default 120s = 2 minutes).
    /// </summary>
    public int ResendCooldownSeconds { get; set; } = 120;

    /// <summary>How many requests are allowed within <see cref="LockoutWindowMinutes"/> before a lockout.</summary>
    public int MaxRequestsPerWindow { get; set; } = 3;

    /// <summary>
    /// Sliding window used to count requests toward the lockout, in minutes. After
    /// <see cref="MaxRequestsPerWindow"/> requests inside this window, further requests are blocked
    /// until the window clears (an hour by default).
    /// </summary>
    public int LockoutWindowMinutes { get; set; } = 60;

    /// <summary>
    /// DEV ONLY: when true the issued code is returned in the API response (and logged) so the flow
    /// can be tested without the real Telesom SMS. MUST be false in production.
    /// </summary>
    public bool ExposeCodeInResponse { get; set; } = true;
}
