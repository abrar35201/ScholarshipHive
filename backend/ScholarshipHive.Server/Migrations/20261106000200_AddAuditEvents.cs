using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using ScholarshipHive.Server.Data;
#nullable disable
namespace ScholarshipHive.Server.Migrations;
[DbContext(typeof(AppDbContext))]
[Migration("20261106000200_AddAuditEvents")]
public partial class AddAuditEvents : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(name: "AuditEvents", columns: table => new
        {
            Id = table.Column<long>(type: "bigint", nullable: false)
                .Annotation("Npgsql:ValueGenerationStrategy", Npgsql.EntityFrameworkCore.PostgreSQL.Metadata.NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
            Actor = table.Column<string>(type: "text", nullable: false),
            EntityType = table.Column<string>(type: "text", nullable: false),
            Action = table.Column<string>(type: "text", nullable: false),
            EntityKey = table.Column<string>(type: "text", nullable: false),
            AtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
        }, constraints: table => table.PrimaryKey("PK_AuditEvents", x => x.Id));
        migrationBuilder.CreateIndex(name: "IX_AuditEvents_AtUtc", table: "AuditEvents", column: "AtUtc");
    }
    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.DropTable("AuditEvents");
}
