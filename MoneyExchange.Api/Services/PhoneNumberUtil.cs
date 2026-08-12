namespace MoneyExchange.Api.Services;

/// <summary>
/// Normalizes phone numbers to a consistent form for matching. Kept in one place so account
/// look-up (sign-up/sign-in), activation-code assignment, and code redemption all compare the
/// same normalized value — otherwise a code "assigned to" a number could fail to match the
/// account that owns it purely because of spacing/formatting differences.
/// </summary>
public static class PhoneNumberUtil
{
    /// <summary>Trims and strips everything but digits and a leading-style '+'.</summary>
    public static string Normalize(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return string.Empty;
        return new string(phone.Where(c => char.IsDigit(c) || c == '+').ToArray());
    }
}
