using Google.Apis.Auth;

namespace MoneyExchange.Api.Services.Auth;

/// <summary>
/// Validates Google ID tokens using Google.Apis.Auth, which checks the signature against
/// Google's published JWKS (cached in-process), plus issuer, audience and expiry. No call to
/// Supabase Auth or any other hosted auth provider is involved.
/// </summary>
public class GoogleTokenVerifier : IGoogleTokenVerifier
{
    private readonly IConfiguration _configuration;

    public GoogleTokenVerifier(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public async Task<GoogleIdentity> VerifyAsync(string idToken, CancellationToken cancellationToken = default)
    {
        var audiences = _configuration.GetSection("GoogleAuth:Audiences").Get<string[]>();
        if (audiences is null || audiences.Length == 0)
            throw new InvalidOperationException("GoogleAuth:Audiences is not configured.");

        var settings = new GoogleJsonWebSignature.ValidationSettings
        {
            Audience = audiences
        };

        GoogleJsonWebSignature.Payload payload;
        try
        {
            payload = await GoogleJsonWebSignature.ValidateAsync(idToken, settings);
        }
        catch (InvalidJwtException ex)
        {
            throw new InvalidGoogleTokenException("Google ID token failed validation.", ex);
        }

        if (!payload.EmailVerified)
            throw new InvalidGoogleTokenException("Google account email is not verified.");

        return new GoogleIdentity(payload.Subject, payload.Email, payload.Name, payload.Picture);
    }
}
