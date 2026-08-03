using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A signed-in identity, established via Google Sign-In. Verified directly against Google's
/// public keys (see <see cref="Services.Auth.IGoogleTokenVerifier"/>) - no third-party auth
/// service (e.g. Supabase Auth) sits in front of this, so there's no per-provider active-user
/// cap or extra network hop on the login path.
/// </summary>
public class User
{
    public int Id { get; set; }

    [Required, MaxLength(320)]
    public string Email { get; set; } = string.Empty;

    /// <summary>The "sub" claim from Google's ID token - Google's stable, unique identifier for this account.</summary>
    [Required, MaxLength(255)]
    public string GoogleSubjectId { get; set; } = string.Empty;

    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? ProfilePictureUrl { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime LastLoginAtUtc { get; set; } = DateTime.UtcNow;
}
