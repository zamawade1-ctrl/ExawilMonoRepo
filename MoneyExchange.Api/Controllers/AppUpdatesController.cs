using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.Responses;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

/// <summary>
/// PUBLIC (no-auth) in-app update feed. The mobile app and the public download
/// page both read the currently-active release from here to decide whether a
/// mandatory update is needed. Explicitly <see cref="AllowAnonymousAttribute"/>
/// so it stays reachable without any token, account, or admin access.
/// </summary>
[AllowAnonymous]
[Route("api/app-updates")]
public class AppUpdatesController : ApiControllerBase
{
    private readonly IAppUpdateRepository _appUpdateRepository;

    public AppUpdatesController(IAppUpdateRepository appUpdateRepository)
    {
        _appUpdateRepository = appUpdateRepository;
    }

    // GET: api/app-updates/android  → the active Android release (public).
    // GET: api/app-updates/{platform} for any other platform.
    [HttpGet("{platform}")]
    public async Task<IActionResult> GetActive(string platform) =>
        HandleResponse(await _appUpdateRepository.GetActiveAsync(platform));

    // GET: api/app-updates/{platform}/download  → counts one download of the active
    // release, then 302-redirects to the public APK URL. The web download button and
    // the app's mandatory-update flow both go through here so downloads are tallied.
    // Public (no auth) and always non-cached so every real click is counted.
    [HttpGet("{platform}/download")]
    public async Task<IActionResult> Download(string platform)
    {
        var result = await _appUpdateRepository.TrackDownloadAsync(platform);
        if (result.Status != ServiceStatus.Success || string.IsNullOrWhiteSpace(result.Data))
            return HandleResponse(result);

        Response.Headers.CacheControl = "no-store";
        return Redirect(result.Data);
    }
}
