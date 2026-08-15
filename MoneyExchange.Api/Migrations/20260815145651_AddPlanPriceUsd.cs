using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MoneyExchange.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddPlanPriceUsd : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "PlanPriceUsd",
                table: "Users",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "PriceUsd",
                table: "ActivationCodes",
                type: "integer",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PlanPriceUsd",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "PriceUsd",
                table: "ActivationCodes");
        }
    }
}
