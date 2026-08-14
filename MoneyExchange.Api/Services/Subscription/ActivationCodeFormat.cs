namespace MoneyExchange.Api.Services.Subscription;

/// <summary>
/// Formatting shared between minting an activation code (admin) and displaying one back to the user
/// on their session poll. The stored form is dash-free + upper-case (e.g. <c>MX4KPA9QTR7WHX</c>); the
/// human form groups the random body into fours after the fixed <see cref="Prefix"/>:
/// <c>MX-4KPA-9QTR-7WHX</c>. Redemption tolerates either form (see <c>SubscriptionRepository.NormalizeCode</c>).
/// </summary>
public static class ActivationCodeFormat
{
    /// <summary>The fixed leading token every code carries, so a code reads as ours at a glance.</summary>
    public const string Prefix = "MX";

    /// <summary>Formats a stored raw code for humans: the prefix, then the body in groups of four.</summary>
    public static string Prettify(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return raw;
        var body = raw.StartsWith(Prefix, StringComparison.Ordinal) ? raw[Prefix.Length..] : raw;
        var groups = new List<string> { Prefix };
        for (var i = 0; i < body.Length; i += 4)
            groups.Add(body.Substring(i, Math.Min(4, body.Length - i)));
        return string.Join('-', groups);
    }
}
