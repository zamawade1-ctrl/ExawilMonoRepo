using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.DTOs.AppUpdate;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Repositories.Implementations;

/// <inheritdoc />
public class AppUpdateRepository : IAppUpdateRepository
{
    private readonly AppDbContext _db;

    public AppUpdateRepository(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ServiceResponse<AppUpdateDto>> GetActiveAsync(string platform)
    {
        var normalized = (platform ?? string.Empty).Trim().ToLowerInvariant();
        if (normalized.Length == 0)
            return ServiceResponse<AppUpdateDto>.BadRequest("A platform is required.");

        // The active release for the platform. If more than one is somehow flagged
        // active, the newest versionCode wins so a stale row can't pin an old build.
        // The ThenByDescending(Id) is a REQUIRED stable tiebreaker: without it, two
        // active rows (or two rows with the same VersionCode) order arbitrarily in
        // Postgres, so this endpoint and TrackDownloadAsync could resolve to DIFFERENT
        // rows — which shipped users a metadata versionName from one row but an APK
        // download from a stale/older row, causing "package appears to be invalid".
        var release = await _db.AppVersions
            .Where(v => v.IsActive && v.Platform == normalized)
            .OrderByDescending(v => v.VersionCode)
            .ThenByDescending(v => v.Id)
            .FirstOrDefaultAsync();

        if (release is null)
            return ServiceResponse<AppUpdateDto>.NotFound(
                $"No active release is configured for '{normalized}'.");

        return ServiceResponse<AppUpdateDto>.Ok(new AppUpdateDto
        {
            Platform = release.Platform,
            VersionName = release.VersionName,
            VersionCode = release.VersionCode,
            ApkUrl = release.ApkUrl,
            ReleaseNotes = release.ReleaseNotes,
            Mandatory = release.Mandatory,
            ReleasedAtUtc = release.ReleasedAtUtc,
            DownloadCount = release.DownloadCount,
        }, "Active release.");
    }

    public async Task<ServiceResponse<string>> TrackDownloadAsync(string platform)
    {
        var normalized = (platform ?? string.Empty).Trim().ToLowerInvariant();
        if (normalized.Length == 0)
            return ServiceResponse<string>.BadRequest("A platform is required.");

        // Same ordering (incl. the stable ThenByDescending(Id) tiebreaker) as
        // GetActiveAsync so the download redirect ALWAYS resolves to the exact same
        // row the metadata endpoint advertised — never a different/older APK.
        var release = await _db.AppVersions
            .Where(v => v.IsActive && v.Platform == normalized)
            .OrderByDescending(v => v.VersionCode)
            .ThenByDescending(v => v.Id)
            .FirstOrDefaultAsync();

        if (release is null)
            return ServiceResponse<string>.NotFound(
                $"No active release is configured for '{normalized}'.");

        // Atomic server-side increment so concurrent downloads can't lose counts
        // (no read-modify-write race). Scoped to this exact row by Id.
        await _db.AppVersions
            .Where(v => v.Id == release.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(v => v.DownloadCount, v => v.DownloadCount + 1));

        return ServiceResponse<string>.Ok(release.ApkUrl, "Download recorded.");
    }
}
