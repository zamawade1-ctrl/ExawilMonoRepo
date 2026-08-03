namespace MoneyExchange.Api.Models.Responses;

/// <summary>
/// The logical outcome of a repository operation. The controller maps each
/// value to the matching HTTP status code — the repository never touches HTTP.
/// </summary>
public enum ServiceStatus
{
    Success = 0,     // 200 OK
    Created = 1,     // 201 Created
    NotFound = 2,    // 404 Not Found
    BadRequest = 3,  // 400 Bad Request
    Conflict = 4,    // 409 Conflict
    Error = 5        // 500 Internal Server Error
}
