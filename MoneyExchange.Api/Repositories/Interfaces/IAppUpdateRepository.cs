using MoneyExchange.Api.Models.DTOs.AppUpdate;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Repositories.Interfaces;

/// <summary>
/// Serves the currently-active mobile release for the public (no-auth) in-app
/// update check. Read-only from the app's side; releases are managed out of band
/// (Supabase row + Storage upload).
/// </summary>
public interface IAppUpdateRepository
{
    /// <summary>
    /// The single active release for <paramref name="platform"/> (case-insensitive),
    /// or NotFound when none is configured. NotFound is a safe "no update known"
    /// signal — the app must not force an update on it.
    /// </summary>
    Task<ServiceResponse<AppUpdateDto>> GetActiveAsync(string platform);

    /// <summary>
    /// Records one download of the active release for <paramref name="platform"/>
    /// (atomic increment) and returns its public APK URL so the caller can redirect
    /// the client to it. NotFound when no active release exists.
    /// </summary>
    Task<ServiceResponse<string>> TrackDownloadAsync(string platform);
}
