using Microsoft.EntityFrameworkCore;
using MoneyExchange.Api.Models.Entities;

namespace MoneyExchange.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<ExchangeTransaction> ExchangeTransactions => Set<ExchangeTransaction>();

    public DbSet<Customer> Customers => Set<Customer>();

    public DbSet<OtpVerification> OtpVerifications => Set<OtpVerification>();

    public DbSet<IncomingMoneyTransaction> IncomingMoneyTransactions => Set<IncomingMoneyTransaction>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ExchangeTransaction>(entity =>
        {
            entity.Property(e => e.Amount).HasColumnType("numeric(18,2)");
            entity.Property(e => e.Rate).HasColumnType("numeric(18,6)");
            entity.Property(e => e.ConvertedAmount).HasColumnType("numeric(18,2)");
            entity.Property(e => e.Status).HasConversion<string>();
        });

        modelBuilder.Entity<Customer>(entity =>
        {
            entity.Property(e => e.ForwardingMethod).HasConversion<string>();
            entity.HasIndex(e => e.PhoneNumber).IsUnique();
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
    }
}
