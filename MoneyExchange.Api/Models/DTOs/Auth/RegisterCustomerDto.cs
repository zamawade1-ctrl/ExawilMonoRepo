using System.ComponentModel.DataAnnotations;
using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>Payload for the customer registration form: identity + where auto-forwarded money should go.</summary>
public class RegisterCustomerDto
{
    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    /// <summary>
    /// Optional. The on-device forwarder reads the account's own number off the
    /// *800# balance screen, so the app no longer collects it. Still used for
    /// Telesom OTP login and server-side receipt matching when supplied.
    /// </summary>
    [MaxLength(20)]
    public string? PhoneNumber { get; set; }

    [Required, EnumDataType(typeof(ForwardingMethod))]
    public ForwardingMethod ForwardingMethod { get; set; }

    /// <summary>Required when <see cref="ForwardingMethod"/> is MobileNumber.</summary>
    [MaxLength(20)]
    public string? ForwardingPhoneNumber { get; set; }

    /// <summary>Required when <see cref="ForwardingMethod"/> is BankAccount.</summary>
    [MaxLength(120)]
    public string? BankName { get; set; }

    [MaxLength(60)]
    public string? BankAccountNumber { get; set; }

    [MaxLength(120)]
    public string? BankAccountHolderName { get; set; }
}