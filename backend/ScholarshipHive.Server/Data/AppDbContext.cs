using Microsoft.AspNetCore.DataProtection.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.AspNetCore.Http;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Data;

/// IDataProtectionKeyContext persists the ASP.NET Data Protection key ring here
/// instead of the container's own local disk — that disk is wiped on every
/// deploy/restart, which silently invalidated every already-open web session's
/// login antiforgery token (and any encrypted cookie) the moment a new
/// container came up, surfacing as a login that hangs or fails right after
/// submitting the form. Keys stored in Postgres survive every redeploy.
public class AppDbContext : DbContext, IDataProtectionKeyContext
{
    private readonly IHttpContextAccessor _requestContext;
    public AppDbContext(DbContextOptions<AppDbContext> options, IHttpContextAccessor requestContext) : base(options)
    { _requestContext = requestContext; }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        => SaveChangesAsync(true, cancellationToken);

    public override async Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default)
    {
        // Only metadata is saved. Do not copy secret fields, credentials, or personal data.
        var changes = ChangeTracker.Entries()
            .Where(e => e.Entity is not AuditEvent && e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .Select(e => (Entry: e, Action: e.State.ToString(), Type: e.Metadata.ClrType.Name,
                Fields: e.State == EntityState.Modified
                    ? string.Join(", ", e.Properties.Where(p => p.IsModified &&
                        p.Metadata.Name != "PasswordHash" && p.Metadata.Name != "FcmToken" &&
                        p.Metadata.Name != "HomeDeviceId" && p.Metadata.Name != "LastDeviceId")
                        .Select(p => p.Metadata.Name).Take(15))
                    : "")).ToList();
        var actor = _requestContext.HttpContext?.User?.Identity?.IsAuthenticated == true
            ? (_requestContext.HttpContext.User.Identity?.Name ?? "Authenticated") : "System";
        var saved = await base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
        if (changes.Count == 0) return saved;
        // ID values are available after the first save (including inserted entities).
        foreach (var change in changes)
        {
            var keyProperty = change.Entry.Properties.FirstOrDefault(p => p.Metadata.IsPrimaryKey());
            AuditEvents.Add(new AuditEvent {
                Actor = actor.Length > 100 ? actor[..100] : actor,
                EntityType = change.Type,
                Action = change.Action,
                EntityKey = keyProperty?.CurrentValue?.ToString() ?? "?",
                Details = change.Fields.Length > 500 ? change.Fields[..500] : change.Fields,
                AtUtc = DateTime.UtcNow
            });
        }
        await base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
        return saved;
    }

    public DbSet<Microsoft.AspNetCore.DataProtection.EntityFrameworkCore.DataProtectionKey> DataProtectionKeys => Set<Microsoft.AspNetCore.DataProtection.EntityFrameworkCore.DataProtectionKey>();

    public DbSet<AuditEvent> AuditEvents => Set<AuditEvent>();
    public DbSet<User> Users => Set<User>();
    public DbSet<Announcement> Announcements => Set<Announcement>();
    public DbSet<UserNotice> UserNotices => Set<UserNotice>();
    public DbSet<ShiftChangeRequest> ShiftChangeRequests => Set<ShiftChangeRequest>();
    public DbSet<LeaveRequest> LeaveRequests => Set<LeaveRequest>();
    public DbSet<VisitorRecord> VisitorRecords => Set<VisitorRecord>();
    public DbSet<CallingFormEntry> CallingFormEntries => Set<CallingFormEntry>();
    public DbSet<ReceptionConsent> ReceptionConsents => Set<ReceptionConsent>();
    public DbSet<Attendance> Attendances => Set<Attendance>();
    public DbSet<Report> Reports => Set<Report>();
    public DbSet<ReportFile> ReportFiles => Set<ReportFile>();
    public DbSet<AllowedRouter> AllowedRouters => Set<AllowedRouter>();
    public DbSet<AllowedLocation> AllowedLocations => Set<AllowedLocation>();
    public DbSet<PendingNetwork> PendingNetworks => Set<PendingNetwork>();
    public DbSet<LoginHistory> LoginHistories => Set<LoginHistory>();
    public DbSet<AuditReport> AuditReports => Set<AuditReport>();
    public DbSet<AuditReportFile> AuditReportFiles => Set<AuditReportFile>();
    public DbSet<PendingPasswordReset> PendingPasswordResets => Set<PendingPasswordReset>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<AuditEvent>().HasIndex(e => e.AtUtc);
        modelBuilder.Entity<UserNotice>().HasIndex(n => new { n.UserId, n.CreatedAt });
        modelBuilder.Entity<Announcement>().HasOne(a => a.Author).WithMany().HasForeignKey(a => a.AuthorId).OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<Announcement>().HasIndex(a => new { a.CreatedAt, a.Department });
        modelBuilder.Entity<Announcement>().HasOne(a => a.LastEditedByUser).WithMany()
            .HasForeignKey(a => a.LastEditedByUserId).OnDelete(DeleteBehavior.SetNull);
        modelBuilder.Entity<ShiftChangeRequest>().HasOne(s => s.User).WithMany().HasForeignKey(s => s.UserId).OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<ShiftChangeRequest>().HasIndex(s => new { s.UserId, s.Status });
        modelBuilder.Entity<ReceptionConsent>().HasIndex(c => c.VisitorRecordId);
        modelBuilder.Entity<LeaveRequest>()
            .HasOne(l => l.User).WithMany().HasForeignKey(l => l.UserId)
            .OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<LeaveRequest>().HasIndex(l => new { l.UserId, l.AppliedAt });
        modelBuilder.Entity<VisitorRecord>().HasIndex(v => v.CheckInTime);
        modelBuilder.Entity<CallingFormEntry>().HasIndex(f => new { f.CreatedByUserId, f.CreatedAt });
        modelBuilder.Entity<CallingFormEntry>().HasIndex(f => f.PublicShareTokenHash).IsUnique();
        modelBuilder.Entity<CallingFormEntry>().HasOne(f => f.CreatedByUser).WithMany().HasForeignKey(f => f.CreatedByUserId).OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<ReceptionConsent>().HasIndex(c => c.CreatedAt);

        modelBuilder.Entity<User>()
            .HasIndex(u => u.Username)
            .IsUnique();

        modelBuilder.Entity<Attendance>()
            .HasOne(a => a.User)
            .WithMany(u => u.Attendances)
            .HasForeignKey(a => a.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<Attendance>()
            .HasIndex(a => new { a.UserId, a.Date })
            .IsUnique();

        modelBuilder.Entity<Report>()
            .HasOne(r => r.User)
            .WithMany()
            .HasForeignKey(r => r.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<Report>()
            .HasOne(r => r.Attendance)
            .WithOne(a => a.Report)
            .HasForeignKey<Report>(r => r.AttendanceId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<ReportFile>()
            .HasOne(f => f.Report)
            .WithMany(r => r.Files)
            .HasForeignKey(f => f.ReportId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<PendingNetwork>()
            .HasIndex(p => p.Bssid)
            .IsUnique();

        modelBuilder.Entity<LoginHistory>()
            .HasOne(h => h.User)
            .WithMany()
            .HasForeignKey(h => h.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<LoginHistory>()
            .HasIndex(h => new { h.UserId, h.Timestamp });

        modelBuilder.Entity<AuditReport>()
            .HasOne(a => a.AuditorUser)
            .WithMany()
            .HasForeignKey(a => a.AuditorUserId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<AuditReportFile>()
            .HasOne(f => f.AuditReport)
            .WithMany(a => a.Files)
            .HasForeignKey(f => f.AuditReportId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<PendingPasswordReset>()
            .HasOne(p => p.User)
            .WithMany()
            .HasForeignKey(p => p.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        modelBuilder.Entity<PendingPasswordReset>()
            .HasIndex(p => p.UserId)
            .IsUnique();
    }
}
