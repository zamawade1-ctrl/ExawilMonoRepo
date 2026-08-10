using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A signed-in identity and its login credentials. Since the switch away from Google Sign-In the
/// primary path is username/email + password (<see cref="PasswordHash"/>); the old Google
/// subject id is kept nullable for the dormant Google path. Each User owns exactly one
/// <see cref="Customer"/> forwarding profile (1-to-1 via <see cref="Customer.UserId"/>), created
/// alongside the User at sign-up.
/// </summary>
public class User
{
    public int Id { get; set; }

    [Required, MaxLength(320)]
    public string Email { get; set; } = string.Empty;

    /// <summary>Login username. Unique (case-insensitive match in the repository).</summary>
    [MaxLength(60)]
    public string? Username { get; set; }

    /// <summary>
    /// PBKDF2 hash of the password (ASP.NET Core <c>PasswordHasher</c> format), never the raw
    /// password. Null only for legacy Google-only identities. <see cref="JsonIgnore"/>d so it's
    /// never serialized out through the API.
    /// </summary>
    [MaxLength(400), JsonIgnore]
    public string? PasswordHash { get; set; }

    /// <summary>The "sub" claim from Google's ID token. Null for password accounts (legacy/dormant Google path).</summary>
    [MaxLength(255)]
    public string? GoogleSubjectId { get; set; }

    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? ProfilePictureUrl { get; set; }

    /// <summary>The forwarding profile owned by this identity (1-to-1). Created at sign-up.</summary>
    public Customer? Customer { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime LastLoginAtUtc { get; set; } = DateTime.UtcNow;
}
