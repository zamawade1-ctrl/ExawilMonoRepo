using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<ExchangeTransaction> ExchangeTransactions => Set<ExchangeTransaction>();

    public DbSet<User> Users => Set<User>();

    public DbSet<Customer> Customers => Set<Customer>();

    public DbSet<OtpVerification> OtpVerifications => Set<OtpVerification>();

    public DbSet<IncomingMoneyTransaction> IncomingMoneyTransactions => Set<IncomingMoneyTransaction>();

    public DbSet<ActivationCode> ActivationCodes => Set<ActivationCode>();

    public DbSet<AppVersion> AppVersions => Set<AppVersion>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ExchangeTransaction>(entity =>
        {
            entity.Property(e => e.Amount).HasColumnType("numeric(18,2)");
            entity.Property(e => e.Rate).HasColumnType("numeric(18,6)");
            entity.Property(e => e.ConvertedAmount).HasColumnType("numeric(18,2)");
            entity.Property(e => e.Status).HasConversion<string>();
        });

        modelBuilder.Entity<User>(entity =>
        {
            // Login credentials live on the identity. Email + Username unique; GoogleSubjectId is
            // now nullable (password accounts have none) - Postgres treats the many NULLs as
            // distinct, so a unique index still works.
            entity.HasIndex(e => e.Email).IsUnique();
            entity.HasIndex(e => e.Username).IsUnique();
            entity.HasIndex(e => e.GoogleSubjectId).IsUnique();
            // Phone is the login identity now; unique (Postgres treats the many NULLs as distinct).
            entity.HasIndex(e => e.PhoneNumber).IsUnique();
            // Store the role as its name ("User"/"Admin") rather than an int, for readable rows.
            entity.Property(e => e.Role).HasConversion<string>().HasMaxLength(20);
            // Soft-deleted accounts are hidden from every normal query (login, auth lookups, admin
            // lists, subscription). Registration's device-history lookup opts back in with
            // IgnoreQueryFilters() so a deleted device still carries its trial-used state forward.
            entity.HasQueryFilter(e => !e.IsDeleted);
        });

        modelBuilder.Entity<ActivationCode>(entity =>
        {
            entity.HasIndex(e => e.Code).IsUnique();
        });

        modelBuilder.Entity<Customer>(entity =>
        {
            entity.Property(e => e.ForwardingMethod).HasConversion<string>();
            entity.HasIndex(e => e.PhoneNumber).IsUnique();
            entity.HasIndex(e => e.UserId).IsUnique();

            // 1-to-1: each User owns one Customer forwarding profile. Deleting the User cascades
            // to its Customer (account deletion removes both).
            entity.HasOne(e => e.User)
                .WithOne(u => u.Customer)
                .HasForeignKey<Customer>(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            // Mirror the User soft-delete filter so a deleted user's forwarding profile is hidden
            // too (and to keep EF from warning about the filtered principal / unfiltered dependent).
            // Legacy anonymously-registered rows (UserId null) stay visible.
            entity.HasQueryFilter(e => e.User == null || !e.User.IsDeleted);
        });

        modelBuilder.Entity<OtpVerification>(entity =>
        {
            entity.HasIndex(e => new { e.PhoneNumber, e.Code });
        });

        modelBuilder.Entity<IncomingMoneyTransaction>(entity =>
        {
            entity.Property(e => e.AmountUsd).HasColumnType("numeric(18,2)");
            entity.Property(e => e.Provider).HasConversion<string>();
            entity.Property(e => e.ForwardStatus).HasConversion<string>();
            entity.HasIndex(e => new { e.Provider, e.ProviderTransactionId }).IsUnique();

            entity.HasOne(e => e.Customer)
                .WithMany()
                .HasForeignKey(e => e.CustomerId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<AppVersion>(entity =>
        {
            // The active-release lookup filters by platform + IsActive, then takes the
            // highest versionCode — index the first two to keep it a cheap point lookup.
            entity.HasIndex(e => new { e.Platform, e.IsActive });
        });
    }
}
