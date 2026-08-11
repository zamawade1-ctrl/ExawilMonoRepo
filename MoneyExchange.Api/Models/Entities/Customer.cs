using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A registered customer's money-forwarding profile: their phone number (used for the future
/// Telesom OTP second factor and for matching incoming Zaad/eDahab receipts) and where
/// auto-forwarded USD should be sent. The login identity + credentials live on the linked
/// <see cref="Entities.User"/> (1-to-1 via <see cref="UserId"/>); a Customer is created
/// alongside its User at sign-up.
/// </summary>
public class Customer
{
    public int Id { get; set; }

    /// <summary>
    /// The <see cref="Entities.User"/> identity this forwarding profile belongs to (1-to-1).
    /// Set at sign-up. Nullable only so legacy anonymously-registered rows still validate.
    /// </summary>
    public int? UserId { get; set; }

    public User? User { get; set; }

    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    /// <summary>
    /// Phone number used for OTP login and for matching incoming Zaad/eDahab receipts.
    /// Nullable: the app no longer collects it (the on-device forwarder reads the account's
    /// own number off the *800# balance screen), so phone-less profiles store null rather than
    /// an empty string - many empty strings would collide on the unique index, but Postgres
    /// treats multiple NULLs as distinct.
    /// </summary>
    [MaxLength(20)]
    public string? PhoneNumber { get; set; }

    /// <summary>
    /// Which rail auto-forwarded money takes (mobile number vs bank account). The
    /// destination itself and the PINs are NOT stored server-side for security —
    /// they live only in the device's on-device store (Android SharedPreferences +
    /// Keystore). This just records the chosen method for management/display.
    /// </summary>
    public ForwardingMethod ForwardingMethod { get; set; }

    /// <summary>
    /// True once the customer is eligible for auto-forwarding. Normally set by completing
    /// Telesom OTP verification; currently defaults to true at registration since the Telesom
    /// API isn't available yet (see CustomerRepository.RegisterAsync). Unverified customers are
    /// not auto-forwarded to.
    /// </summary>
    public bool IsVerified { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public enum ForwardingMethod
{
    MobileNumber = 0,
    BankAccount = 1
}