using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ScholarshipHive.Server.Migrations
{
    /// <inheritdoc />
    public partial class UnifyLoginHistoryEventTypes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Old scheme: Login=0, Checkin=1, Logout=2. New scheme: CheckIn=0, CheckOut=1.
            // Login and Checkin were always semantically the same event ("arrived") — an
            // admin never needed to know which mechanism caused it. Remaps without losing
            // any history: Logout(2) moves out of the way to a temp value first so it
            // doesn't collide with Checkin(1) being renumbered to CheckIn(0) in the same pass.
            migrationBuilder.Sql("UPDATE \"LoginHistories\" SET \"EventType\" = 99 WHERE \"EventType\" = 2;");
            migrationBuilder.Sql("UPDATE \"LoginHistories\" SET \"EventType\" = 0 WHERE \"EventType\" = 1;");
            migrationBuilder.Sql("UPDATE \"LoginHistories\" SET \"EventType\" = 1 WHERE \"EventType\" = 99;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Best-effort only — the original Login-vs-Checkin distinction can't be
            // recovered once merged, so every CheckIn is restored as a Checkin (1).
            migrationBuilder.Sql("UPDATE \"LoginHistories\" SET \"EventType\" = 2 WHERE \"EventType\" = 1;");
            migrationBuilder.Sql("UPDATE \"LoginHistories\" SET \"EventType\" = 1 WHERE \"EventType\" = 0;");
        }
    }
}
