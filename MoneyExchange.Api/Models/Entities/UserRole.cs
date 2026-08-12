namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// Access level of an account. Regular customers are <see cref="User"/>; <see cref="Admin"/>s reach
/// the admin surface (generate activation codes, expire plans, reset devices/passwords, view all
/// plans). Stored as a string column and carried in the JWT as a role claim.
/// </summary>
public enum UserRole
{
    User = 0,
    Admin = 1
}
