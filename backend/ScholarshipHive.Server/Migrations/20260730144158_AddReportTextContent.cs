using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddReportTextContent : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "TextContent",
                table: "Reports",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "TextContent",
                table: "Reports");
        }
    }
}
