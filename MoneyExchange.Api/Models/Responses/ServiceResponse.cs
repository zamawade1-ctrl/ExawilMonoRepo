namespace MoneyExchange.Api.Models.Responses;

/// <summary>
/// Uniform wrapper returned by every repository method. Carries the payload,
/// a human-readable message and a logical <see cref="ServiceStatus"/> that the
/// controller translates into an HTTP status code.
/// </summary>
public class ServiceResponse<T>
{
    public T? Data { get; set; }

    public string Message { get; set; } = string.Empty;

    public ServiceStatus Status { get; set; } = ServiceStatus.Success;

    // Convenience factory helpers so repositories read cleanly.
    public static ServiceResponse<T> Ok(T data, string message = "Request completed successfully.") =>
        new() { Data = data, Message = message, Status = ServiceStatus.Success };

    public static ServiceResponse<T> CreatedResult(T data, string message = "Resource created successfully.") =>
        new() { Data = data, Message = message, Status = ServiceStatus.Created };

    public static ServiceResponse<T> NotFound(string message = "Resource not found.") =>
        new() { Data = default, Message = message, Status = ServiceStatus.NotFound };

    public static ServiceResponse<T> BadRequest(string message = "The request was invalid.") =>
        new() { Data = default, Message = message, Status = ServiceStatus.BadRequest };

    public static ServiceResponse<T> Conflict(string message = "The request conflicts with the current state.") =>
        new() { Data = default, Message = message, Status = ServiceStatus.Conflict };

    public static ServiceResponse<T> Error(string message = "An unexpected error occurred.") =>
        new() { Data = default, Message = message, Status = ServiceStatus.Error };
}
