using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddReportFileAttachment : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "Content",
                table: "Reports",
                type: "character varying(4000)",
                maxLength: 4000,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "character varying(4000)",
                oldMaxLength: 4000);

            migrationBuilder.AddColumn<string>(
                name: "ContentType",
                table: "Reports",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "FileData",
                table: "Reports",
                type: "bytea",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "FileName",
                table: "Reports",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ContentType",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "FileData",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "FileName",
                table: "Reports");

            migrationBuilder.AlterColumn<string>(
                name: "Content",
                table: "Reports",
                type: "character varying(4000)",
                maxLength: 4000,
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "character varying(4000)",
                oldMaxLength: 4000,
                oldNullable: true);
        }
    }
}
