using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Services;

public record DayDuration(int Minutes, bool StillOpen, int GapMinutes = 0);

/// Real accumulated presence time, built from the LoginHistory audit trail (every
/// CheckIn/CheckOut event) rather than the Attendance table's single CheckInTime/
/// CheckOutTime pair — which only ever remembers the day's FIRST check-in and LAST
/// check-out, and so silently overcounts any gap where the employee actually left and
/// came back (lunch, a dropped connection, a shared-device switch, etc.). Shared by the
/// mobile shift-timer progress bar and the admin per-user Hours breakdown so both agree
/// on exactly the same number.
public class AttendanceDurationService
{
    private readonly AppDbContext _db;
    // Maximum plausible uninterrupted shift used only for displaying totals.
    // Longer historical gaps (typically missing checkout events) require
    // review; never count multi-day gaps as worked time.
    private const int MaxSingleShiftMinutes = 9 * 60;

    public AttendanceDurationService(AppDbContext db)
    {
        _db = db;
    }

    // Business day `d` runs from 07:00 Pakistan time on `d` to 07:00 on `d+1`, which
    // in UTC (PKT is a fixed UTC+5) is [d 02:00 UTC, d+1 02:00 UTC) — see
    // DateTimeExtensions.PakistanDateOf, which this is the exact inverse of.
    // DateOnly.ToDateTime always produces Kind=Unspecified, which Npgsql rejects for a
    // "timestamp with time zone" column — it must be explicitly marked Utc (see the
    // matching fix in UsersController.DayHistory).
    private static DateTime BusinessDayStartUtc(DateOnly d) => DateTime.SpecifyKind(d.ToDateTime(TimeOnly.MinValue).AddHours(2), DateTimeKind.Utc);

    /// Minutes of real accumulated presence per business day across [from, to]
    /// (inclusive), for one user. `asOfUtc` caps whatever cycle is still open (normally
    /// DateTime.UtcNow) so "today, right now" only counts time actually elapsed so far.
    public async Task<Dictionary<DateOnly, DayDuration>> ComputeAsync(int userId, DateOnly from, DateOnly to, DateTime asOfUtc)
    {
        var history = await _db.LoginHistories
            .Where(h => h.UserId == userId && h.Timestamp >= BusinessDayStartUtc(from) && h.Timestamp < BusinessDayStartUtc(to.AddDays(1)))
            .OrderBy(h => h.Timestamp)
            .ToListAsync();

        return PairCycles(history, asOfUtc);
    }

    /// Same as ComputeAsync, but for many users in a single query — used by the admin
    /// Hours list, which otherwise would issue one LoginHistory query per employee.
    public async Task<Dictionary<int, Dictionary<DateOnly, DayDuration>>> ComputeManyAsync(IReadOnlyCollection<int> userIds, DateOnly from, DateOnly to, DateTime asOfUtc)
    {
        var startUtc = BusinessDayStartUtc(from);
        var endUtc = BusinessDayStartUtc(to.AddDays(1));

        var history = await _db.LoginHistories
            .Where(h => userIds.Contains(h.UserId) && h.Timestamp >= startUtc && h.Timestamp < endUtc)
            .OrderBy(h => h.Timestamp)
            .ToListAsync();

        var byUser = history.GroupBy(h => h.UserId).ToDictionary(g => g.Key, g => PairCycles(g.ToList(), asOfUtc));
        // Every requested user gets an entry, even one with zero LoginHistory rows in range.
        foreach (var id in userIds) byUser.TryAdd(id, new Dictionary<DateOnly, DayDuration>());
        return byUser;
    }

    private static Dictionary<DateOnly, DayDuration> PairCycles(List<LoginHistory> history, DateTime asOfUtc)
    {
        var byDay = new Dictionary<DateOnly, DayDuration>();
        DateTime? pendingCheckIn = null;
        DateTime? lastCompletedCheckout = null;

        // A gap is recorded only between a completed checkout and the next check-in
        // in the SAME Pakistan business day. Open intervals and orphan events are
        // not counted as gaps; this is a display-only calculation.
        void AddGap(DateTime checkout, DateTime nextCheckin)
        {
            if (nextCheckin < checkout) return;
            var day = DateTimeExtensions.PakistanDateOf(nextCheckin);
            if (DateTimeExtensions.PakistanDateOf(checkout) != day) return;
            var minutes = Math.Max(0, (int)(nextCheckin - checkout).TotalMinutes);
            var existing = byDay.GetValueOrDefault(day, new DayDuration(0, false));
            byDay[day] = existing with { GapMinutes = existing.GapMinutes + minutes };
        }

        void AddMinutes(DateOnly day, int minutes, bool stillOpen)
        {
            var existing = byDay.GetValueOrDefault(day, new DayDuration(0, false));
            // 9 hours credited work per business day maximum, across all
            // reconnects; never turn a missed checkout into 200+ hours.
            byDay[day] = new DayDuration(Math.Min(9 * 60, existing.Minutes + minutes),
                existing.StillOpen || stillOpen, existing.GapMinutes);
        }

        foreach (var h in history.OrderBy(h => h.Timestamp))
        {
            if (h.EventType == LoginHistoryEvent.CheckIn)
            {
                if (pendingCheckIn is null && lastCompletedCheckout is DateTime co)
                    AddGap(co, h.Timestamp);
                lastCompletedCheckout = null;
                pendingCheckIn = h.Timestamp;
            }
            else if (pendingCheckIn is DateTime ci)
            {
                // A cycle that crosses the 7 AM boundary (an overnight shift) is
                // attributed to the day it ends on — matching the mobile app's own
                // groupHistoryByDay pairing convention.
                var day = DateTimeExtensions.PakistanDateOf(h.Timestamp);
                var elapsed = Math.Max(0, (int)(h.Timestamp - ci).TotalMinutes);
                AddMinutes(day, Math.Min(elapsed, MaxSingleShiftMinutes), false);
                pendingCheckIn = null;
                lastCompletedCheckout = h.Timestamp;
            }
        }

        if (pendingCheckIn is DateTime openCi)
        {
            var day = DateTimeExtensions.PakistanDateOf(openCi);
            var dayEndUtc = BusinessDayStartUtc(day.AddDays(1));
            var cap = asOfUtc < dayEndUtc ? asOfUtc : dayEndUtc;
            AddMinutes(day, Math.Min(MaxSingleShiftMinutes, Math.Max(0, (int)(cap - openCi).TotalMinutes)), true);
        }

        return byDay;
    }
}
