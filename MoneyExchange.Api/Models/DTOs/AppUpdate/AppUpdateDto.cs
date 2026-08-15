namespace MoneyExchange.Api.Models.DTOs.AppUpdate;

/// <summary>
/// The public payload returned by <c>GET /api/app-updates/{platform}</c> — the
/// currently-active release for a platform. Contains only what the app needs to
/// decide on and perform an update; no server-internal fields.
/// </summary>
public class AppUpdateDto
{
    public string Platform { get; set; } = "android";

    public string VersionName { get; set; } = string.Empty;

    /// <summary>The build number the app compares against its installed build.</summary>
    public long VersionCode { get; set; }

    /// <summary>Public HTTPS URL of the signed APK to download.</summary>
    public string ApkUrl { get; set; } = string.Empty;

    public string? ReleaseNotes { get; set; }

    public bool Mandatory { get; set; }

    public DateTime ReleasedAtUtc { get; set; }
}
