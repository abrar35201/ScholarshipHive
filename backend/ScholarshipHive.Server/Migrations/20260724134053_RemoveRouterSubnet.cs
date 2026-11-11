using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class RemoveRouterSubnet : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Subnet",
                table: "AllowedRouters");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Subnet",
                table: "AllowedRouters",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);
        }
    }
}
