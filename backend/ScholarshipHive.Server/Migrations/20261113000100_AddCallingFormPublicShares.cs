using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using ScholarshipHive.Server.Data;
#nullable disable
namespace ScholarshipHive.Server.Migrations;
[DbContext(typeof(AppDbContext))]
[Migration("20261113000100_AddCallingFormPublicShares")]
public partial class AddCallingFormPublicShares : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTime>(name:"PublicShareCreatedAt",table:"CallingFormEntries",type:"timestamp with time zone",nullable:true);
        migrationBuilder.AddColumn<string>(name:"PublicShareTokenHash",table:"CallingFormEntries",type:"character varying(64)",maxLength:64,nullable:true);
        migrationBuilder.CreateIndex(name:"IX_CallingFormEntries_PublicShareTokenHash",table:"CallingFormEntries",column:"PublicShareTokenHash",unique:true);
    }
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(name:"IX_CallingFormEntries_PublicShareTokenHash",table:"CallingFormEntries");
        migrationBuilder.DropColumn(name:"PublicShareCreatedAt",table:"CallingFormEntries");
        migrationBuilder.DropColumn(name:"PublicShareTokenHash",table:"CallingFormEntries");
    }
}
