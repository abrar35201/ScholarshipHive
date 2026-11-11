using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddAttendanceLastPingAt : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "LastPingAt",
                table: "Attendances",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            // Existing open attendances would otherwise default to year 0001, which the
            // new stale-checkout sweep would immediately treat as "silent for 2 minutes"
            // and auto-checkout everyone currently connected the moment this deploys.
            migrationBuilder.Sql("UPDATE \"Attendances\" SET \"LastPingAt\" = NOW() WHERE \"CheckOutTime\" IS NULL;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "LastPingAt",
                table: "Attendances");
        }
    }
}
