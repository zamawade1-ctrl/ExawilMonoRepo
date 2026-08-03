using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>Payload to request a Telesom OTP code for a registered phone number.</summary>
public class RequestOtpDto
{
    [Required, MaxLength(20)]
    public string PhoneNumber { get; set; } = string.Empty;
}