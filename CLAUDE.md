# MoneyExchange.Api

ASP.NET Core (.NET 10) Web API for a money-exchange / auto-forwarding service. Customers
register with a phone number and a payout preference (mobile number or bank account). A
background job polls Zaad and eDahab every minute for USD received on that phone number and
auto-forwards it to the customer's chosen destination.

## Stack

- ASP.NET Core 10, EF Core 10
- **Postgres via Supabase**, accessed through `Npgsql.EntityFrameworkCore.PostgreSQL` — this is
  a normal EF Core + Postgres setup, not the Supabase JS/Auth SDK. There is no Node/JS in this
  repo; don't add `@supabase/*` npm packages here.
- JWT bearer auth (`Microsoft.AspNetCore.Authentication.JwtBearer`)

## Architecture pattern

Repository pattern + `ServiceResponse<T>` wrapper: controllers are thin, repositories hold all
business + persistence logic and return a `ServiceResponse<T>` with a logical `ServiceStatus`.
`ApiControllerBase.HandleResponse<T>` maps that status to the HTTP status code. Controllers
never talk to `AppDbContext` directly.

```
Controllers/          thin, one action per repository method
Repositories/
  Interfaces/          contract, returns ServiceResponse<T>
  Implementations/      all validation + EF Core queries live here
Models/
  Entities/             EF Core entities
  DTOs/                 request payloads
  Responses/            ServiceResponse<T> / ServiceStatus
Services/
  Otp/                  Telesom OTP (stub)
  MoneyProviders/        Zaad / eDahab polling clients (stub)
  Forwarding/            USSD/bank forwarding + the 1-minute background job
  Auth/                  JWT issuance
Migrations/            EF Core migrations (Postgres)
```

## Domain flow

1. `POST /api/customers` — the registration form: name, phone number, and forwarding choice
   (`ForwardingMethod.MobileNumber` + `ForwardingPhoneNumber`, or `ForwardingMethod.BankAccount`
   + bank fields). Anonymous.
2. `POST /api/auth/otp/request` / `POST /api/auth/otp/verify` — Telesom OTP login flow, issues a
   JWT. **Currently not required** — see "OTP is bypassed" below.
3. Every 60 seconds, `MoneyForwardingBackgroundService` polls `IMoneyProviderClient` for Zaad and
   eDahab, matches each USD receipt to a `Customer` by phone number, and forwards it via
   `IMoneyForwardingService` to that customer's mobile number or bank account. Every attempt is
   recorded in `IncomingMoneyTransaction` (deduped by provider transaction id), visible via
   `GET /api/incomingmoneytransactions`.

## OTP is bypassed for now

The Telesom OTP API isn't available yet, so `CustomerRepository.RegisterAsync` sets
`Customer.IsVerified = true` immediately at registration instead of requiring the OTP round
trip. The auth scaffold (`AuthController`, `ITelesomOtpService`, `OtpVerification` entity, JWT
issuance) is fully built and still works if called — it's just not required for a customer to
receive auto-forwarded money. When the real Telesom API is available: implement
`ITelesomOtpService` for real, and change that one line back to `IsVerified = false`.

## Stub integrations — swap points

Three external integrations are interfaces with logging stubs, each ready to be replaced with a
real implementation without touching any other code:

| Interface | Stub impl | Real thing |
|---|---|---|
| `ITelesomOtpService` | `TelesomOtpService` | Telesom SMS/OTP API |
| `IMoneyProviderClient` | `ZaadMoneyProviderClient`, `EDahabMoneyProviderClient` | Zaad / eDahab receipt-polling APIs |
| `IMoneyForwardingService` | `UssdMoneyForwardingService` | USSD gateway / bank transfer rail |

All three are registered in `Program.cs`. Swap the implementation registration when real
credentials/API docs are available — nothing else needs to change.

## Database: Supabase Postgres

Uses **EF Core Migrations**, not `EnsureCreated()`. This matters: Supabase's built-in schemas
(`auth`, `storage`, ...) already contain tables, which makes `EnsureCreated()`'s "does this
database already have a schema" check report `true` and silently skip creating the app's own
tables. `Program.cs` calls `db.Database.Migrate()` on startup instead.

**Connection string**: use the **Session pooler** string from the Supabase dashboard
(Project → Connect → ORMs, or Settings → Database → Connection pooling), not the direct
`db.<project-ref>.supabase.co` host — that host is IPv6-only and unreachable from most
networks/laptops. The pooler host looks like `aws-<n>-<region>.pooler.supabase.com`; get the
region from *this* project specifically (copying a pooler host from a different Supabase
project fails with "tenant/user not found").

Format:
```
Host=aws-<n>-<region>.pooler.supabase.com;Port=5432;Database=postgres;Username=postgres.<project-ref>;Password=<db-password>;SSL Mode=Require;Trust Server Certificate=true
```

### Local setup

Never put real credentials in `appsettings.json` — it's committed to git. Use user-secrets
instead (already wired via `UserSecretsId` in the `.csproj`):

```bash
cd MoneyExchange.Api
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Host=...;Port=5432;Database=postgres;Username=postgres.<project-ref>;Password=...;SSL Mode=Require;Trust Server Certificate=true"
dotnet user-secrets set "Jwt:Key" "$(openssl rand -base64 48)"
```

For actual hosting (not local dev), use environment variables with double-underscore nesting
instead: `ConnectionStrings__DefaultConnection`, `Jwt__Key`.

### Migrations workflow

```bash
cd MoneyExchange.Api
dotnet ef migrations add <Name>     # after changing an entity / OnModelCreating
dotnet ef database update           # apply pending migrations to the configured DefaultConnection
```

`dotnet run` also applies pending migrations automatically on startup.

## Running locally

```bash
cd MoneyExchange.Api
dotnet run
```

Requires `ConnectionStrings:DefaultConnection` and `Jwt:Key` to be set via user-secrets (see
above) — the app will fail to start without a real connection string, by design (no secrets
baked into the repo).