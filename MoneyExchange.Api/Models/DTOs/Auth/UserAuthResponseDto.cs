using MoneyExchange.Api.Models.DTOs.Subscription;

namespace MoneyExchange.Api.Models.DTOs.Auth;

/// <summary>Returned after a successful sign-up, sign-in, or Google sign-in.</summary>
public class UserAuthResponseDto
{
    public string AccessToken { get; set; } = string.Empty;

    public DateTime ExpiresAtUtc { get; set; }

    public int UserId { get; set; }

    /// <summary>The forwarding profile created for / owned by this user (1-to-1).</summary>
    public int? CustomerId { get; set; }

    public string? Email { get; set; }

    public string? Username { get; set; }

    /// <summary>The login identity (phone number) for the phone/password flow.</summary>
    public string? PhoneNumber { get; set; }

    public string FullName { get; set; } = string.Empty;

    public string? ProfilePictureUrl { get; set; }

    /// <summary>Whether the user has set their 6-digit app-lock PIN yet (drives the set-PIN gate).</summary>
    public bool HasAppPin { get; set; }

    /// <summary>Whether the app-lock PIN is enabled at all (a user can turn it off in settings).</summary>
    public bool PinEnabled { get; set; } = true;

    /// <summary>"User" or "Admin" — drives whether the app shows the admin surface.</summary>
    public string Role { get; set; } = "User";

    /// <summary>The trial/plan snapshot at sign-in, so the client can gate + show the countdown at once.</summary>
    public PlanStatusDto Plan { get; set; } = new();
}
