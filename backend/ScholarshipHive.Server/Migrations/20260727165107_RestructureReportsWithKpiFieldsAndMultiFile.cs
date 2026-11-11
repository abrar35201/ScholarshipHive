using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class RestructureReportsWithKpiFieldsAndMultiFile : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Content",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "ContentType",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "FileData",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "FileName",
                table: "Reports");

            migrationBuilder.AddColumn<int>(
                name: "Calls",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "Conversion",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "FollowUp",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTime>(
                name: "LastEditedAt",
                table: "Reports",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "NewLeads",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "Potential",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "QualifiedLeads",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "UnreadChats",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "WalkIns",
                table: "Reports",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateTable(
                name: "ReportFiles",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ReportId = table.Column<int>(type: "integer", nullable: false),
                    FileName = table.Column<string>(type: "text", nullable: false),
                    ContentType = table.Column<string>(type: "text", nullable: true),
                    FileData = table.Column<byte[]>(type: "bytea", nullable: false),
                    UploadedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ReportFiles", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ReportFiles_Reports_ReportId",
                        column: x => x.ReportId,
                        principalTable: "Reports",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ReportFiles_ReportId",
                table: "ReportFiles",
                column: "ReportId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ReportFiles");

            migrationBuilder.DropColumn(
                name: "Calls",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "Conversion",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "FollowUp",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "LastEditedAt",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "NewLeads",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "Potential",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "QualifiedLeads",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "UnreadChats",
                table: "Reports");

            migrationBuilder.DropColumn(
                name: "WalkIns",
                table: "Reports");

            migrationBuilder.AddColumn<string>(
                name: "Content",
                table: "Reports",
                type: "character varying(4000)",
                maxLength: 4000,
                nullable: true);

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
    }
}
