using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A registered customer: their phone number (used for Telesom OTP login and
/// for matching incoming Zaad/eDahab receipts) and where auto-forwarded USD
/// should be sent.
/// </summary>
public class Customer
{
    public int Id { get; set; }

    /// <summary>
    /// The signed-in identity (Google account) this forwarding profile belongs to, if the
    /// customer signed in via the app. Nullable for now - the registration form can still be
    /// filled out standalone; the app wires this up once a signed-in user completes it.
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

    public ForwardingMethod ForwardingMethod { get; set; }

    /// <summary>Destination mobile number when <see cref="ForwardingMethod"/> is MobileNumber.</summary>
    [MaxLength(20)]
    public string? ForwardingPhoneNumber { get; set; }

    [MaxLength(120)]
    public string? BankName { get; set; }

    [MaxLength(60)]
    public string? BankAccountNumber { get; set; }

    [MaxLength(120)]
    public string? BankAccountHolderName { get; set; }

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