namespace MoneyExchange.Api.Models.DTOs.Subscription;

/// <summary>
/// A snapshot of a user's access state, returned by the auth + subscription endpoints. The client
/// caches the timestamps and derives a live countdown from them against its own clock, using
/// <see cref="ServerNowUtc"/> to correct for clock drift, so the trial timer keeps ticking offline
/// between refreshes.
/// </summary>
public class PlanStatusDto
{
    /// <summary>"Trial", "Pro", or "Expired" (the <c>PlanStatus</c> enum name).</summary>
    public string Status { get; set; } = "Trial";

    /// <summary>When the free trial ends (trial-start + the configured trial length).</summary>
    public DateTime TrialEndsAtUtc { get; set; }

    /// <summary>When the paid plan is valid through, or null if the user has never paid.</summary>
    public DateTime? PlanPaidUntilUtc { get; set; }

    /// <summary>The server's current UTC time, so the client can correct for clock drift.</summary>
    public DateTime ServerNowUtc { get; set; }

    /// <summary>How many days one activation/payment grants (for display).</summary>
    public int PlanDays { get; set; }

    /// <summary>
    /// Start of the currently-active window (trial start when on Trial, plan start when Pro), or null
    /// when expired. With <see cref="CurrentPeriodEndUtc"/> this lets the client draw a progress ring.
    /// </summary>
    public DateTime? CurrentPeriodStartUtc { get; set; }

    /// <summary>End of the currently-active window (trial end when on Trial, paid-until when Pro), or null when expired.</summary>
    public DateTime? CurrentPeriodEndUtc { get; set; }
}

/// <summary>
/// The signed-in session's live validity + plan, polled by the app every few seconds so an admin
/// action takes effect in near-real-time. <see cref="Valid"/> is false once the caller's device no
/// longer matches the account's bound device (e.g. after an admin device-reset), which the app
/// treats as "sign out now so the account can re-bind on the next login from any device".
/// </summary>
public class SessionStatusDto
{
    /// <summary>Whether this device's session is still valid (device still bound to this device id).</summary>
    public bool Valid { get; set; } = true;

    /// <summary>Why the session was invalidated, when <see cref="Valid"/> is false (for logging/UX).</summary>
    public string? Reason { get; set; }

    /// <summary>The current plan snapshot, so the same poll also drives the expiry gate.</summary>
    public PlanStatusDto Plan { get; set; } = new();
}
