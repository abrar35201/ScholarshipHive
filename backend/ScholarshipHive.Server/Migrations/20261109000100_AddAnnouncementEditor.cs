using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using ScholarshipHive.Server.Data;
#nullable disable
namespace ScholarshipHive.Server.Migrations;
[DbContext(typeof(AppDbContext))]
[Migration("20261109000100_AddAnnouncementEditor")]
public partial class AddAnnouncementEditor : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // PostgreSQL deployments keep all existing announcements; the new editor is optional.
        migrationBuilder.Sql(@"ALTER TABLE ""AuditEvents"" ADD COLUMN IF NOT EXISTS ""Details"" character varying(500) NULL;");
        migrationBuilder.Sql(@"ALTER TABLE ""Announcements"" ADD COLUMN IF NOT EXISTS ""LastEditedByUserId"" integer NULL;");
        migrationBuilder.Sql(@"CREATE INDEX IF NOT EXISTS ""IX_Announcements_LastEditedByUserId"" ON ""Announcements""(""LastEditedByUserId"");");
        migrationBuilder.Sql(@"DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_Announcements_Users_LastEditedByUserId') THEN
            ALTER TABLE ""Announcements"" ADD CONSTRAINT ""FK_Announcements_Users_LastEditedByUserId""
              FOREIGN KEY (""LastEditedByUserId"") REFERENCES ""Users""(""Id"") ON DELETE SET NULL;
          END IF;
        END $$;");
    }
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(@"ALTER TABLE ""AuditEvents"" DROP COLUMN IF EXISTS ""Details"";");
        migrationBuilder.Sql(@"ALTER TABLE ""Announcements"" DROP CONSTRAINT IF EXISTS ""FK_Announcements_Users_LastEditedByUserId"";");
        migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Announcements_LastEditedByUserId"";");
        migrationBuilder.Sql(@"ALTER TABLE ""Announcements"" DROP COLUMN IF EXISTS ""LastEditedByUserId"";");
    }
}
