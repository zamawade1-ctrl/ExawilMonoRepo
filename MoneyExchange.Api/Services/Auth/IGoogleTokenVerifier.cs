namespace MoneyExchange.Api.Services.Auth;

public record GoogleIdentity(string Subject, string Email, string FullName, string? ProfilePictureUrl);

/// <summary>
/// Verifies a Google ID token's signature and claims directly against Google's public keys.
/// This is a plain JWT verification (no per-request call to a hosted auth service), so it has
/// no active-user cap and no added latency beyond the (cached) public key fetch.
/// </summary>
public interface IGoogleTokenVerifier
{
    Task<GoogleIdentity> VerifyAsync(string idToken, CancellationToken cancellationToken = default);
}

/// <summary>Thrown when a Google ID token fails signature, audience, issuer, or expiry validation.</summary>
public class InvalidGoogleTokenException : Exception
{
    public InvalidGoogleTokenException(string message, Exception? inner = null) : base(message, inner)
    {
    }
}
