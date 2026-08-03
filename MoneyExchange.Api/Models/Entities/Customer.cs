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

    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    /// <summary>Phone number used for OTP login and for matching incoming Zaad/eDahab receipts.</summary>
    [Required, MaxLength(20)]
    public string PhoneNumber { get; set; } = string.Empty;

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