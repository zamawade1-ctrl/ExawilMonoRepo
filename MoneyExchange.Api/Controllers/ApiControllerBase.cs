using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.Responses;

namespace MoneyExchange.Api.Controllers;

/// <summary>
/// Base controller that turns a <see cref="ServiceResponse{T}"/> coming out of a
/// repository into the correct HTTP status code. Controllers stay thin: they call
/// a repository method and hand the result to <see cref="HandleResponse{T}"/>.
/// </summary>
[ApiController]
public abstract class ApiControllerBase : ControllerBase
{
    protected IActionResult HandleResponse<T>(ServiceResponse<T> response) =>
        response.Status switch
        {
            ServiceStatus.Success => Ok(response),
            ServiceStatus.Created => StatusCode(StatusCodes.Status201Created, response),
            ServiceStatus.NotFound => NotFound(response),
            ServiceStatus.BadRequest => BadRequest(response),
            ServiceStatus.Conflict => Conflict(response),
            ServiceStatus.Error => StatusCode(StatusCodes.Status500InternalServerError, response),
            _ => StatusCode(StatusCodes.Status500InternalServerError, response)
        };

    /// <summary>
    /// Extracts the signed-in <c>User</c> id from the JWT, for endpoints scoped to "me".
    /// Only accepts tokens issued by the Google sign-in flow (<c>subjectType=user</c>) -
    /// a phone/OTP-issued token's subject is a Customer id, not a User id, and must not be
    /// treated as one.
    /// </summary>
    protected bool TryGetAuthenticatedUserId(out int userId)
    {
        userId = 0;

        if (User.FindFirstValue("subjectType") != "user")
            return false;

        var subject = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue(JwtRegisteredClaimNames.Sub);
        return int.TryParse(subject, out userId);
    }

    /// <summary>
    /// Extracts the signed-in <c>Customer</c> id from the JWT, for endpoints scoped to "me".
    /// The Customer is the authenticated identity in the phone/password flow, so its token's
    /// subject is a Customer id (<c>subjectType=customer</c>). A legacy Google user token is
    /// rejected here - its subject is a User id, not a Customer id.
    /// </summary>
    protected bool TryGetAuthenticatedCustomerId(out int customerId)
    {
        customerId = 0;

        if (User.FindFirstValue("subjectType") != "customer")
            return false;

        var subject = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue(JwtRegisteredClaimNames.Sub);
        return int.TryParse(subject, out customerId);
    }
}
