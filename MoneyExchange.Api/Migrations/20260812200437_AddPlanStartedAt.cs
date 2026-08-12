using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MoneyExchange.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddPlanStartedAt : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "PlanStartedAtUtc",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PlanStartedAtUtc",
                table: "Users");
        }
    }
}
