using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddUserShiftFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Explicit 09:00/18:00 defaults (not EF's usual midnight) — every
            // existing employee needs a sane shift the moment this column
            // exists, or they'd all read as arriving ~9 hours "late" the
            // instant this migration runs.
            migrationBuilder.AddColumn<TimeOnly>(
                name: "ShiftEndTime",
                table: "Users",
                type: "time without time zone",
                nullable: false,
                defaultValue: new TimeOnly(18, 0, 0));

            migrationBuilder.AddColumn<TimeOnly>(
                name: "ShiftStartTime",
                table: "Users",
                type: "time without time zone",
                nullable: false,
                defaultValue: new TimeOnly(9, 0, 0));

            migrationBuilder.AddColumn<int>(
                name: "ShiftType",
                table: "Users",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ShiftEndTime",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "ShiftStartTime",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "ShiftType",
                table: "Users");
        }
    }
}
