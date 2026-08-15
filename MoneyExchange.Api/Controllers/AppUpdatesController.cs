using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
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
}
