using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using ScholarshipHive.Server.Data;
#nullable disable
namespace ScholarshipHive.Server.Migrations;
[DbContext(typeof(AppDbContext))]
[Migration("20261112223500_AddCallingFormEntries")]
public partial class AddCallingFormEntries : Migration
{
  protected override void Up(MigrationBuilder m)
  {
    m.CreateTable(name:"CallingFormEntries", columns: table => new {
        Id=table.Column<int>(type:"integer",nullable:false).Annotation("Npgsql:ValueGenerationStrategy",Npgsql.EntityFrameworkCore.PostgreSQL.Metadata.NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
        CreatedByUserId=table.Column<int>(type:"integer",nullable:false),
        TemplateId=table.Column<string>(type:"character varying(80)",maxLength:80,nullable:false),
        ApplicantName=table.Column<string>(type:"character varying(120)",maxLength:120,nullable:false),
        Phone=table.Column<string>(type:"character varying(40)",maxLength:40,nullable:false),
        Email=table.Column<string>(type:"character varying(150)",maxLength:150,nullable:true),
        AnswersJson=table.Column<string>(type:"character varying(14000)",maxLength:14000,nullable:false),
        CreatedAt=table.Column<DateTime>(type:"timestamp with time zone",nullable:false)
    }, constraints: table => {table.PrimaryKey("PK_CallingFormEntries",x=>x.Id);table.ForeignKey("FK_CallingFormEntries_Users_CreatedByUserId",x=>x.CreatedByUserId,"Users","Id",onDelete:ReferentialAction.Restrict);});
    m.CreateIndex(name:"IX_CallingFormEntries_CreatedByUserId_CreatedAt",table:"CallingFormEntries",columns:new[]{"CreatedByUserId","CreatedAt"});
  }
  protected override void Down(MigrationBuilder m) => m.DropTable("CallingFormEntries");
}
