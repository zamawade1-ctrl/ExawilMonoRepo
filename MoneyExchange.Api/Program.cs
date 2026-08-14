using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Models.Entities;
using MoneyExchange.Api.Repositories.Implementations;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services.Auth;
using MoneyExchange.Api.Services.Forwarding;
using MoneyExchange.Api.Services.MoneyProviders;
using MoneyExchange.Api.Services.Otp;
using MoneyExchange.Api.Services.Subscription;

var builder = WebApplication.CreateBuilder(args);

// Hosting platforms (Render, Railway, Fly, …) inject the port to listen on via the
// PORT env var and terminate TLS at their proxy, forwarding plain HTTP to the
// container. Bind to 0.0.0.0:$PORT so the proxy can reach the app. Locally PORT is
// unset, so the usual launch URLs / --urls apply unchanged.
var listenPort = Environment.GetEnvironmentVariable("PORT");
if (!string.IsNullOrWhiteSpace(listenPort))
{
    builder.WebHost.UseUrls($"http://0.0.0.0:{listenPort}");
}

// --- Persistence: EF Core + Postgres (Supabase) ---
// Keep one warm connection in the pool with TCP keepalive so the first request after an idle
// spell doesn't pay the Supabase pooler's cold reconnect (which shows up as a multi-second login).
// The base connection string stays in user-secrets/env; we only layer pooling knobs on top here.
var baseConnection = builder.Configuration.GetConnectionString("DefaultConnection");
var dbConnection = baseConnection;
if (!string.IsNullOrWhiteSpace(baseConnection))
{
    dbConnection = new Npgsql.NpgsqlConnectionStringBuilder(baseConnection)
    {
        MinPoolSize = 1,   // hold a physical connection open so it's ready on the next request
        KeepAlive = 30,    // send TCP keepalives so the pooler doesn't drop the idle connection
    }.ConnectionString;
}
builder.Services.AddDbContext<AppDbContext>(options => options.UseNpgsql(dbConnection));

// --- Repository registration (repository pattern) ---
builder.Services.AddScoped<IExchangeTransactionRepository, ExchangeTransactionRepository>();
builder.Services.AddScoped<ICustomerRepository, CustomerRepository>();
builder.Services.AddScoped<IAuthRepository, AuthRepository>();
builder.Services.AddScoped<IIncomingMoneyTransactionRepository, IncomingMoneyTransactionRepository>();
builder.Services.AddScoped<IUserAuthRepository, UserAuthRepository>();
builder.Services.AddScoped<IPinRepository, PinRepository>();
builder.Services.AddScoped<ISubscriptionRepository, SubscriptionRepository>();
builder.Services.AddScoped<IAdminRepository, AdminRepository>();

// --- Trial + paid-plan config and the status calculator ---
builder.Services.Configure<SubscriptionOptions>(
    builder.Configuration.GetSection(SubscriptionOptions.SectionName));
builder.Services.AddScoped<PlanCalculator>();

// --- Telesom OTP: stub until the real Telesom API integration is wired in ---
builder.Services.AddScoped<ITelesomOtpService, TelesomOtpService>();
builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();

// --- Password hashing for sign-up/sign-in (PBKDF2, ASP.NET Core's hasher) ---
builder.Services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();

// --- Google Sign-In: verified directly against Google's public keys, no hosted auth provider ---
builder.Services.AddScoped<IGoogleTokenVerifier, GoogleTokenVerifier>();

// --- Zaad / eDahab: stub clients until the real provider APIs are wired in ---
builder.Services.AddScoped<IMoneyProviderClient, ZaadMoneyProviderClient>();
builder.Services.AddScoped<IMoneyProviderClient, EDahabMoneyProviderClient>();

// --- Forwarding: stub until the real USSD gateway / bank-transfer integration is wired in ---
builder.Services.AddScoped<IMoneyForwardingService, UssdMoneyForwardingService>();

// --- Runs every 1 minute: polls Zaad/eDahab and auto-forwards received USSD ---
builder.Services.AddHostedService<MoneyForwardingBackgroundService>();

var jwtSection = builder.Configuration.GetSection("Jwt");
var jwtKey = jwtSection["Key"] ?? throw new InvalidOperationException("Jwt:Key is not configured.");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtSection["Issuer"],
            ValidateAudience = true,
            ValidAudience = jwtSection["Audience"],
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddAuthorization();

// --- CORS: let the admin web console (a browser SPA on a different origin) call the API ---
// Origins are configurable so localhost (Vite dev) and the hosted Vercel domain can both be
// allowed without a code change. Configure via Cors:AllowedOrigins (array) in appsettings /
// env (Cors__AllowedOrigins__0, ...). Falls back to the Vite dev server if unset.
const string AdminWebCorsPolicy = "AdminWebCors";
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>();
if (allowedOrigins is null || allowedOrigins.Length == 0)
{
    allowedOrigins = ["http://localhost:5173", "http://127.0.0.1:5173"];
}
builder.Services.AddCors(options =>
{
    options.AddPolicy(AdminWebCorsPolicy, policy => policy
        .WithOrigins(allowedOrigins)
        .AllowAnyHeader()
        .AllowAnyMethod());
});

builder.Services.AddControllers();
builder.Services.AddOpenApi();

var app = builder.Build();

// Apply pending EF Core migrations on startup. EnsureCreated() is deliberately not used:
// on Supabase, tables already exist in built-in schemas (auth, storage, ...), which makes
// EnsureCreated's "does the database already have a schema" check falsely report true and
// skip creating our own tables.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();

    // Normalize rows that predate the Role/PinEnabled columns: the migration backfilled Role with an
    // empty string, which the string→enum converter can't read. Set those to 'User', and keep the
    // app-lock PIN on for accounts that already had one so they aren't silently unlocked.
    db.Database.ExecuteSqlRaw("UPDATE \"Users\" SET \"Role\" = 'User' WHERE \"Role\" NOT IN ('User','Admin');");
    db.Database.ExecuteSqlRaw("UPDATE \"Users\" SET \"PinEnabled\" = TRUE WHERE \"AppPinHash\" IS NOT NULL AND \"PinEnabled\" = FALSE;");

    // Bootstrap the admin account from config (Admin:Phone / Admin:Password / Admin:FullName). This
    // is the trust anchor for the whole admin surface — created if missing, and always ensured to
    // have the Admin role. Without it there'd be no way to get the first admin JWT.
    var adminPhone = builder.Configuration["Admin:Phone"];
    var adminPassword = builder.Configuration["Admin:Password"];
    if (!string.IsNullOrWhiteSpace(adminPhone) && !string.IsNullOrWhiteSpace(adminPassword))
    {
        var normalizedAdminPhone = MoneyExchange.Api.Services.PhoneNumberUtil.Normalize(adminPhone);
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<User>>();
        var admin = db.Users.FirstOrDefault(u => u.PhoneNumber == normalizedAdminPhone);
        if (admin is null)
        {
            admin = new User
            {
                FullName = builder.Configuration["Admin:FullName"] ?? "Administrator",
                PhoneNumber = normalizedAdminPhone,
                Role = UserRole.Admin,
                PinEnabled = false,   // the admin console doesn't use the customer app-lock PIN
                CreatedAt = DateTime.UtcNow,
                LastLoginAtUtc = DateTime.UtcNow
            };
            admin.PasswordHash = hasher.HashPassword(admin, adminPassword);
            db.Users.Add(admin);
        }
        else
        {
            admin.Role = UserRole.Admin;   // ensure an existing account is (re)promoted to admin
        }
        db.SaveChanges();
    }
}

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// Behind a TLS-terminating platform proxy (Render/etc.) the container serves plain
// HTTP, so only enforce HTTPS redirection outside that setup (i.e. local dev over
// https). In production the proxy already serves the public URL over HTTPS.
if (!app.Environment.IsProduction())
{
    app.UseHttpsRedirection();
}
app.UseCors(AdminWebCorsPolicy);
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// Anonymous health check for the hosting platform (Render healthCheckPath=/health).
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();
