using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MoneyExchange.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddAdminCodesAndDeviceLock : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "DeviceId",
                table: "Users",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DeviceLabel",
                table: "Users",
                type: "character varying(120)",
                maxLength: 120,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "DeviceRegisteredAtUtc",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AssignedToPhone",
                table: "ActivationCodes",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ExpiresAtUtc",
                table: "ActivationCodes",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DeviceId",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "DeviceLabel",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "DeviceRegisteredAtUtc",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "AssignedToPhone",
                table: "ActivationCodes");

            migrationBuilder.DropColumn(
                name: "ExpiresAtUtc",
                table: "ActivationCodes");
        }
    }
}
