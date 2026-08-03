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
}
