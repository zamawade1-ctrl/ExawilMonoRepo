using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MoneyExchange.Api.Migrations
{
    /// <inheritdoc />
    public partial class RemoveCustomerDestinationAndPinColumns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "BankAccountHolderName",
                table: "Customers");

            migrationBuilder.DropColumn(
                name: "BankAccountNumber",
                table: "Customers");

            migrationBuilder.DropColumn(
                name: "BankName",
                table: "Customers");

            migrationBuilder.DropColumn(
                name: "ForwardingPhoneNumber",
                table: "Customers");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "BankAccountHolderName",
                table: "Customers",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BankAccountNumber",
                table: "Customers",
                type: "character varying(60)",
                maxLength: 60,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BankName",
                table: "Customers",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ForwardingPhoneNumber",
                table: "Customers",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);
        }
    }
}
