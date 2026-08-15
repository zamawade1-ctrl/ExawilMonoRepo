using System.ComponentModel.DataAnnotations;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A published release of one of the mobile apps, used to drive the mandatory
/// in-app update flow. The public endpoint <c>GET /api/app-updates/{platform}</c>
/// returns the single <see cref="IsActive"/> row for a platform; the app compares
/// its installed build number with <see cref="VersionCode"/> and forces an update
/// when the server's is higher. The APK itself lives in Supabase Storage (a public
/// HTTPS URL in <see cref="ApkUrl"/>) — not inside this project — so releases are
/// added without redeploying the API.
/// </summary>
public class AppVersion
{
    public int Id { get; set; }

    /// <summary>Target platform, lower-cased, e.g. "android" (iOS can't self-install).</summary>
    [Required, MaxLength(20)]
    public string Platform { get; set; } = "android";

    /// <summary>Human-readable version, e.g. "1.2.0". Shown to the user.</summary>
    [Required, MaxLength(40)]
    public string VersionName { get; set; } = string.Empty;

    /// <summary>
    /// Android versionCode / build number. This — not <see cref="VersionName"/> — is
    /// the value the app compares against its installed build to decide on an update.
    /// </summary>
    public long VersionCode { get; set; }

    /// <summary>Public HTTPS URL of the signed APK (Supabase Storage).</summary>
    [Required, MaxLength(500)]
    public string ApkUrl { get; set; } = string.Empty;

    /// <summary>What changed in this release. Optional; shown on the update screen.</summary>
    public string? ReleaseNotes { get; set; }

    /// <summary>
    /// Whether this release is a forced update. The app additionally enforces any
    /// release whose <see cref="VersionCode"/> exceeds the installed build.
    /// </summary>
    public bool Mandatory { get; set; } = true;

    /// <summary>
    /// The one active release per platform that the public endpoint serves. Setting a
    /// new active release supersedes the previous one.
    /// </summary>
    public bool IsActive { get; set; } = true;

    public DateTime ReleasedAtUtc { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// How many times this release's APK has been downloaded through the public
    /// tracking redirect (<c>GET /api/app-updates/{platform}/download</c>). Both the
    /// web download page and the app's mandatory-update flow go through it, so this
    /// counts real download starts across both. Surfaced on the public download page.
    /// </summary>
    public long DownloadCount { get; set; }
}
