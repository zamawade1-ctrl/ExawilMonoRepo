using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>Payload from the Flutter app after google_sign_in returns an ID token.</summary>
public class GoogleSignInDto
{
    [Required]
    public string IdToken { get; set; } = string.Empty;
}
