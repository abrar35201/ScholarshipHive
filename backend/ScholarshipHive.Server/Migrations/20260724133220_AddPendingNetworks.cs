using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddPendingNetworks : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PendingNetworks",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Bssid = table.Column<string>(type: "text", nullable: false),
                    Ssid = table.Column<string>(type: "text", nullable: true),
                    LastSeenFromIp = table.Column<string>(type: "text", nullable: true),
                    AttemptCount = table.Column<int>(type: "integer", nullable: false),
                    FirstSeenAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    LastSeenAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PendingNetworks", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PendingNetworks_Bssid",
                table: "PendingNetworks",
                column: "Bssid",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PendingNetworks");
        }
    }
}
