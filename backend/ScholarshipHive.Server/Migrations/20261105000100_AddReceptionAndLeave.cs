using System;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using ScholarshipHive.Server.Data;
#nullable disable
namespace ScholarshipHive.Server.Migrations;
[DbContext(typeof(AppDbContext))]
[Migration("20261105000100_AddReceptionAndLeave")]
public partial class AddReceptionAndLeave : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(name: "LeaveRequests", columns: table => new
        {
            Id = table.Column<int>(type: "integer", nullable: false).Annotation("Npgsql:ValueGenerationStrategy", Npgsql.EntityFrameworkCore.PostgreSQL.Metadata.NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
            UserId = table.Column<int>(type: "integer", nullable: false),
            LeaveType = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
            LeaveDate = table.Column<DateOnly>(type: "date", nullable: false),
            Reason = table.Column<string>(type: "character varying(1500)", maxLength: 1500, nullable: false),
            Status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
            AppliedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
            ReviewedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
            ReviewedByUserId = table.Column<int>(type: "integer", nullable: true),
            AdminNote = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true)
        }, constraints: table => { table.PrimaryKey("PK_LeaveRequests", x => x.Id); table.ForeignKey("FK_LeaveRequests_Users_UserId", x => x.UserId, "Users", "Id", onDelete: ReferentialAction.Cascade); });
        migrationBuilder.CreateTable(name: "VisitorRecords", columns: table => new
        {
            Id = table.Column<int>(type: "integer", nullable: false).Annotation("Npgsql:ValueGenerationStrategy", Npgsql.EntityFrameworkCore.PostgreSQL.Metadata.NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
            FullName = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
            Contact = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
            Email = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
            Qualification = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
            Country = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
            Program = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
            InquiryType = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
            Counsellor = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
            Remarks = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
            RegisteredByUserId = table.Column<int>(type: "integer", nullable: false),
            CheckInTime = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
            CheckOutTime = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
        }, constraints: table => table.PrimaryKey("PK_VisitorRecords", x => x.Id));
        migrationBuilder.CreateTable(name: "ReceptionConsents", columns: table => new
        {
            Id = table.Column<int>(type: "integer", nullable: false).Annotation("Npgsql:ValueGenerationStrategy", Npgsql.EntityFrameworkCore.PostgreSQL.Metadata.NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
            ClientFullName = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
            FamilyName = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
            Gender = table.Column<string>(type: "character varying(25)", maxLength: 25, nullable: false),
            DomicileCity = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
            CnicNumber = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
            PhoneNumber = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
            PassportNumber = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
            FullAddress = table.Column<string>(type: "character varying(350)", maxLength: 350, nullable: false),
            QualificationDetails = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: false),
            PolicyVariant = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
            TotalPackageFee = table.Column<int>(type: "integer", nullable: false),
            CounselorName = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
            Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
            CreatedByUserId = table.Column<int>(type: "integer", nullable: false),
            CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
            SignedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
        }, constraints: table => table.PrimaryKey("PK_ReceptionConsents", x => x.Id));
        migrationBuilder.CreateIndex(name:"IX_ReceptionConsents_CreatedAt",table:"ReceptionConsents",column:"CreatedAt");
        migrationBuilder.CreateIndex(name:"IX_LeaveRequests_UserId_AppliedAt", table:"LeaveRequests",columns:new[]{"UserId","AppliedAt"});
        migrationBuilder.CreateIndex(name:"IX_VisitorRecords_CheckInTime",table:"VisitorRecords",column:"CheckInTime");
    }
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name:"ReceptionConsents");
        migrationBuilder.DropTable(name:"VisitorRecords");
        migrationBuilder.DropTable(name:"LeaveRequests");
    }
}
