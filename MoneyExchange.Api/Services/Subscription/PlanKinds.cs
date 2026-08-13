namespace MoneyExchange.Api.Services.Subscription;

/// <summary>
/// Maps a plan's granted duration (in minutes) to a human "plan kind" label — 1 month / 6 months /
/// 1 year / Forever — for the admin surface. A code minted as "Forever" carries
/// <see cref="ForeverMinutes"/>, which redeems to a plan ~4000 years out (effectively never
/// expiring) and labels as "Forever".
/// </summary>
public static class PlanKinds
{
    public const int MinutesPerDay = 24 * 60;
    public const int MonthMinutes = 30 * MinutesPerDay;      // 43,200
    public const int SixMonthMinutes = 182 * MinutesPerDay;  // ~262,080
    public const int YearMinutes = 365 * MinutesPerDay;      // 525,600

    /// <summary>Sentinel for a never-expiring plan (int.MaxValue minutes ≈ 4085 years).</summary>
    public const int ForeverMinutes = int.MaxValue;

    /// <summary>Anything granting ≥ 50 years is treated as "Forever".</summary>
    private const long ForeverThresholdMinutes = 50L * 365 * MinutesPerDay;

    /// <summary>The label shown to the admin for a plan of <paramref name="minutes"/> minutes, or null.</summary>
    public static string? Label(int? minutes)
    {
        if (minutes is not int m || m <= 0) return null;
        if (m >= ForeverThresholdMinutes) return "Forever";

        var day = MinutesPerDay;
        if (Math.Abs(m - MonthMinutes) <= day) return "1 month";
        if (Math.Abs(m - SixMonthMinutes) <= 3 * day) return "6 months";
        if (Math.Abs(m - YearMinutes) <= 3 * day) return "1 year";

        var days = m / day;
        if (days >= 1) return $"{days} day{(days == 1 ? "" : "s")}";
        return $"{m} min";
    }
}
