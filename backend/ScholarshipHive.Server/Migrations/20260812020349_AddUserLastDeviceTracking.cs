using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddUserLastDeviceTracking : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "LastDeviceId",
                table: "Users",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "LastDeviceLoginAt",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "LastDeviceId",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "LastDeviceLoginAt",
                table: "Users");
        }
    }
}
