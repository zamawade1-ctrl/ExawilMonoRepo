using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using MoneyExchange.Api.Data;
using MoneyExchange.Api.Repositories.Implementations;
using MoneyExchange.Api.Repositories.Interfaces;
using MoneyExchange.Api.Services.Auth;
using MoneyExchange.Api.Services.Forwarding;
using MoneyExchange.Api.Services.MoneyProviders;
using MoneyExchange.Api.Services.Otp;

var builder = WebApplication.CreateBuilder(args);

// --- Persistence: EF Core + Postgres (Supabase) ---
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// --- Repository registration (repository pattern) ---
builder.Services.AddScoped<IExchangeTransactionRepository, ExchangeTransactionRepository>();
builder.Services.AddScoped<ICustomerRepository, CustomerRepository>();
builder.Services.AddScoped<IAuthRepository, AuthRepository>();
builder.Services.AddScoped<IIncomingMoneyTransactionRepository, IncomingMoneyTransactionRepository>();

// --- Telesom OTP: stub until the real Telesom API integration is wired in ---
builder.Services.AddScoped<ITelesomOtpService, TelesomOtpService>();
builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();

// --- Zaad / eDahab: stub clients until the real provider APIs are wired in ---
builder.Services.AddScoped<IMoneyProviderClient, ZaadMoneyProviderClient>();
builder.Services.AddScoped<IMoneyProviderClient, EDahabMoneyProviderClient>();

// --- Forwarding: stub until the real USSD gateway / bank-transfer integration is wired in ---
builder.Services.AddScoped<IMoneyForwardingService, UssdMoneyForwardingService>();

// --- Runs every 1 minute: polls Zaad/eDahab and auto-forwards received USD ---
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
}

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
