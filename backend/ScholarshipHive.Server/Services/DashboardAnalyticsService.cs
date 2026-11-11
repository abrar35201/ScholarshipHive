using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Services;

public record RosterEntry(int UserId, string Name, string Department, string? CheckInLabel, string? CheckOutLabel, string Status);

/// One shift type's genuine attendance health over the last 30 days — Day and
/// Night only. Internship shift (the interns) is deliberately excluded here and
/// from the PunctualityRatePct stat card alongside it: interns run on a
/// fundamentally different, much shorter daily window (4 hours vs. a full shift),
/// so folding them into the same rate would just water down what the regular
/// workforce's numbers actually mean, not add anything genuinely comparable.
public record ShiftHealth(string ShiftLabel, int PresentToday, int ActiveEmployees, int AttendanceRatePct30d, int PunctualityRatePct30d);

public record DashboardAnalytics(
    List<ChartPoint> WeeklyHeadcount,
    List<ChartPoint> ArrivalCurve,
    int PresentOnTimeToday,
    int LateToday,
    int AbsentToday,
    List<ShiftHealth> ShiftHealth,
    int TotalActiveEmployees,
    int CheckedInNow,
    int AwayCount,
    string AverageArrivalLabel,
    string AverageArrivalSublabel,
    int AverageArrivalTrendMinutes,
    int ReportsFiledRate,
    string ReportsFiledFraction,
    int ReportsFiledTrendPct,
    int PunctualityRatePct,
    int PunctualityRateTrendPct,
    List<RosterEntry> Roster,
    List<DayRosterDto> DailyBreakdown
);

/// Shared by the web dashboard (Home/Index) and the mobile admin API
/// (Api/AdminController.Dashboard) so both surfaces compute the exact same
/// numbers from the exact same queries, rather than two independently
/// maintained copies that could quietly drift apart.
public class DashboardAnalyticsService
{
    private readonly AppDbContext _db;

    public DashboardAnalyticsService(AppDbContext db)
    {
        _db = db;
    }

    /// The later of `windowStart` and the business day this person actually
    /// joined on — see AnalyticsService.EffectiveStart for the full reasoning
    /// (same fix, duplicated here rather than cross-wired between the two
    /// services), including why `earliestAttendance` has to win over
    /// User.CreatedAt when it's earlier: CreatedAt isn't reliable for anyone
    /// carried over from the old Railway account migration.
    private static DateOnly EffectiveStart(User u, DateOnly windowStart, DateOnly? earliestAttendance = null)
    {
        var joined = DateTimeExtensions.PakistanDateOf(u.CreatedAt);
        if (earliestAttendance.HasValue && earliestAttendance.Value < joined) joined = earliestAttendance.Value;
        return joined > windowStart ? joined : windowStart;
    }

    private static int CountWorkingDays(DateOnly from, DateOnly to, bool isIntern)
    {
        var count = 0;
        for (var d = from; d <= to; d = d.AddDays(1))
        {
            if (!d.DayOfWeek.IsWeekendOff(isIntern)) count++;
        }
        return count;
    }

    public async Task<DashboardAnalytics> ComputeAsync(string period = "day")
    {
        var today = DateTimeExtensions.PakistanToday();
        var weekAgo = today.AddDays(-6);

        // Weekly headcount — how many distinct people had at least one
        // attendance record on each of the last 7 days.
        var weekDates = await _db.Attendances
            .Where(a => a.Date >= weekAgo && a.Date <= today &&
                a.User != null && a.User.Role == UserRole.Employee && a.User.IsActive && a.User.IsApproved)
            .Select(a => a.Date)
            .ToListAsync();
        var weekCounts = weekDates.GroupBy(d => d).ToDictionary(g => g.Key, g => g.Count());
        var weeklyHeadcount = new List<ChartPoint>();
        for (var d = weekAgo; d <= today; d = d.AddDays(1))
        {
            weeklyHeadcount.Add(new ChartPoint(d.ToString("ddd"), weekCounts.GetValueOrDefault(d)));
        }

        // Arrival curve — NEW check-ins landing in each hour of the FULL business
        // day (7 AM today through 7 AM tomorrow — see DateTimeExtensions.
        // DayRolloverHour), not a running cumulative total. A cumulative curve
        // only ever climbs (it can never legitimately come back down, since
        // nobody "un-checks-in"), which reads as broken/stuck once it flattens
        // out for the day — this shows the actual arrival pattern instead (a
        // rush-hour peak, then tapering off), which is what "check-ins through
        // the day" actually means. Each Attendance row is one per (UserId, Date)
        // — see the IX_Attendances_UserId_Date unique constraint — and
        // CheckInTime is set once at creation and never overwritten (see
        // AuthController's Checkin), so this is always each person's one real
        // first-arrival timestamp for today, never a duplicate or a later
        // re-login overwriting it. Bucketing by elapsed time since the business
        // day's own start (rather than raw clock hour-of-day) also means a
        // post-midnight arrival lands near the END of this curve where it
        // actually belongs, instead of wrapping around to look like an
        // impossibly early one.
        var todayCheckIns = await _db.Attendances
            .Where(a => a.Date == today &&
                a.User != null && a.User.Role == UserRole.Employee && a.User.IsActive && a.User.IsApproved)
            .Select(a => a.CheckInTime)
            .ToListAsync();
        var businessDayStartUtc = DateTimeExtensions.BusinessDayStartUtc(today);
        var arrivalCurve = new List<ChartPoint>();
        var previousCutoffUtc = businessDayStartUtc;
        for (var hoursSinceStart = 1; hoursSinceStart <= 24; hoursSinceStart++)
        {
            var cutoffUtc = businessDayStartUtc.AddHours(hoursSinceStart);
            var label = cutoffUtc.ToPakistanTime().ToString("h tt");
            var count = todayCheckIns.Count(t => t > previousCutoffUtc && t <= cutoffUtc);
            arrivalCurve.Add(new ChartPoint(label, count));
            previousCutoffUtc = cutoffUtc;
        }

        // Status split today — "late" is relative to each employee's own
        // ShiftStartTime (see AttendanceRules.IsLateFor), not one fixed cutoff.
        // Excludes accounts still awaiting admin approval — a pending
        // self-registration can't check in at all yet (see
        // AuthController.Login/Checkin), so counting it here just showed up as
        // a permanent, unavoidable "Absent" until someone approved it.
        //
        // Everyone below this point that needs "today's attendance for active
        // employees" (status split, checked-in-now, shift health's presentToday,
        // the roster) reuses THIS one fetch instead of re-querying — this whole
        // method used to make well over a dozen sequential round-trips to
        // Postgres for a single dashboard load, which is what made it feel slow;
        // most of them were re-fetching data already sitting in memory from a
        // handful of queries earlier in the same request.
        var employees = await _db.Users.Where(u => u.IsActive && u.IsApproved && u.Role == UserRole.Employee).OrderBy(u => u.Username).ToListAsync();
        var activeEmployeeCount = employees.Count;
        var todayEmployeeAttendance = await _db.Attendances
            .Include(a => a.User)
            .Where(a => a.Date == today && a.User!.Role == UserRole.Employee && a.User.IsActive && a.User.IsApproved)
            .ToListAsync();
        var lateToday = todayEmployeeAttendance.Count(a => a.CheckInTime.IsLateFor(a.User!.ShiftStartTime));
        var presentOnTimeToday = todayEmployeeAttendance.Count - lateToday;
        var absentToday = Math.Max(activeEmployeeCount - todayEmployeeAttendance.Count, 0);

        // Shift health — genuine 30-day attendance + punctuality rate per shift
        // (Day, Night). This is what actually tells an admin something actionable
        // ("Night shift's attendance rate slipped this month") instead of the old
        // Calling-only "leads handled" number, which said nothing about the other
        // three departments and nothing about shift patterns at all. Internship
        // shift (the interns) is deliberately excluded — see ShiftHealth's doc comment.
        var monthStart = today.AddDays(-29);

        // Unapproved (pending) accounts can't check in yet — including them
        // here just dragged every shift's rate down with unavoidable "absent"
        // days until someone approved them. isIntern: false throughout — Day/
        // Night shifts only ever land here, and Saturday is an ordinary
        // working day for both of them (only Interns, excluded above, have it
        // off too).
        var shiftUsers = employees.Where(u => u.ShiftType != ShiftType.Internship).ToList();
        var shiftUserIds = shiftUsers.Select(u => u.Id).ToHashSet();

        // One query for all Day+Night members' 30-day attendance, grouped by
        // shift in memory afterward — was previously two separate DB round-trips
        // PER shift (a "present today" count plus a 30-day fetch), multiplying
        // with however many shift types exist.
        var shiftMonthAttendanceAll = await _db.Attendances
            .Include(a => a.User)
            .Where(a => a.Date >= monthStart && a.Date <= today && shiftUserIds.Contains(a.UserId))
            .ToListAsync();
        var todayAttendanceByShiftMember = todayEmployeeAttendance
            .Where(a => shiftUserIds.Contains(a.UserId))
            .ToLookup(a => a.User!.ShiftType);

        var shiftHealth = new List<ShiftHealth>();
        foreach (var g in shiftUsers.GroupBy(u => u.ShiftType).OrderBy(g => g.Key))
        {
            var shift = g.Key;
            var memberIds = g.Select(u => u.Id).ToHashSet();
            var memberCount = memberIds.Count;
            var presentToday = todayAttendanceByShiftMember[shift].Count();

            var shiftMonthAttendance = shiftMonthAttendanceAll.Where(a => memberIds.Contains(a.UserId)).ToList();
            var attended = shiftMonthAttendance.Count;
            var onTime = shiftMonthAttendance.Count(a => !a.CheckInTime.IsLateFor(a.User!.ShiftStartTime));
            var earliestAttendanceByMember = shiftMonthAttendance
                .GroupBy(a => a.UserId)
                .ToDictionary(x => x.Key, x => x.Min(a => a.Date));
            // Each member's own working-day count from their own join date —
            // not a blanket headcount x days, which understated the rate for
            // anyone hired within the last 30 days (see AnalyticsService's
            // EffectiveStart doc comment for the full reasoning, including why
            // their own earliest attendance record — not just CreatedAt — has
            // to floor this).
            var expected = g.Sum(u =>
            {
                DateOnly? earliest = earliestAttendanceByMember.TryGetValue(u.Id, out var ea) ? ea : null;
                return CountWorkingDays(EffectiveStart(u, monthStart, earliest), today, isIntern: false);
            });
            // Clamped to 100 as a backstop only (e.g. someone genuinely
            // attending on their own day off) — EffectiveStart's earliest-
            // attendance floor above is what actually keeps this honest.
            var attendanceRate = expected > 0 ? Math.Min(attended * 100 / expected, 100) : 0;
            // 0, not 100, when nobody in this shift has attended at all in the
            // window — "100% punctual" with zero actual attendance to back it
            // up read as a false "perfect" score instead of "no data yet".
            var punctualityRate = attended > 0 ? onTime * 100 / attended : 0;

            shiftHealth.Add(new ShiftHealth(shift.ToString(), presentToday, memberCount, attendanceRate, punctualityRate));
        }

        // ----- Today-page stat cards: On floor / Average arrival / Reports filed / Punctuality rate -----

        var checkedInNow = todayEmployeeAttendance.Count(a => a.CheckOutTime == null);
        var awayCount = Math.Max(activeEmployeeCount - checkedInNow, 0);

        var (start, end, prevStart, prevEnd) = GetRange(period, today);
        // "day" (the default landing view) means start == end == today — reuse
        // todayEmployeeAttendance instead of firing the exact same query again.
        var cur = period == "day" ? ComputePeriodFrom(todayEmployeeAttendance) : await ComputePeriodAsync(start, end);
        var prev = await ComputePeriodAsync(prevStart, prevEnd);

        string averageArrivalLabel;
        string averageArrivalSublabel;
        if (cur.ReportsDenom == 0)
        {
            averageArrivalLabel = "—";
            averageArrivalSublabel = "No check-ins yet";
        }
        else
        {
            // Deviation from each person's OWN shift start, not a clock time —
            // used to reconstruct one absolute "average arrival" clock time
            // anchored at a fixed 9 AM for literally everyone, which fell
            // apart the moment Night shift (starting around 6 PM) existed
            // alongside Day shift: averaging a 9 AM-relative Day check-in with
            // a ~+540-minute Night one produced a single clock time that
            // meant nothing for either group. A relative "Xm late/early"
            // figure is the only thing that's still meaningful once people
            // are compared against different shift starts.
            var deltaMinutes = (int)Math.Round(cur.AvgArrivalMinutesFromShiftStart);
            averageArrivalLabel = deltaMinutes switch
            {
                0 => "On time",
                < 0 => $"{Math.Abs(deltaMinutes)}m early",
                _ => $"{deltaMinutes}m late",
            };
            averageArrivalSublabel = "vs. own shift start";
        }
        var averageArrivalTrendMinutes = prev.ReportsDenom == 0 || cur.ReportsDenom == 0
            ? 0
            : (int)Math.Round(cur.AvgArrivalMinutesFromShiftStart - prev.AvgArrivalMinutesFromShiftStart);

        var reportsFiledRate = cur.ReportsDenom > 0 ? (int)Math.Round(100.0 * cur.ReportsNum / cur.ReportsDenom) : 0;
        var reportsFiledFraction = $"{cur.ReportsNum} of {cur.ReportsDenom}";
        var prevReportsRate = prev.ReportsDenom > 0 ? 100.0 * prev.ReportsNum / prev.ReportsDenom : 0;
        var reportsFiledTrendPct = TrendPct(reportsFiledRate, prevReportsRate);

        var punctualityRatePct = cur.PunctualityDenom > 0 ? (int)Math.Round(100.0 * cur.PunctualityNum / cur.PunctualityDenom) : 0;
        var prevPunctualityRate = prev.PunctualityDenom > 0 ? 100.0 * prev.PunctualityNum / prev.PunctualityDenom : 0;
        var punctualityRateTrendPct = TrendPct(punctualityRatePct, prevPunctualityRate);

        // ----- Live roster — every active employee, today's status -----

        List<RosterEntry> BuildRoster(Dictionary<int, Attendance> attendanceByUser)
        {
            // Sort by the real CheckInTime, not the formatted label — "hh:mm tt"
            // strings ("02:30 PM" vs "09:15 AM") don't sort chronologically as
            // plain text, unlike the old 24-hour "HH:mm" labels this replaced.
            var rows = new List<(RosterEntry Entry, DateTime? SortKey)>();
            foreach (var u in employees)
            {
                var name = u.FullName?.Length > 0 ? u.FullName : u.Username;
                var dept = u.Department.ToString();
                if (attendanceByUser.TryGetValue(u.Id, out var att))
                {
                    var pk = att.CheckInTime.ToPakistanTime();
                    var status = att.CheckInTime.IsLateFor(u.ShiftStartTime) ? "Late" : (att.CheckOutTime != null ? "CheckedOut" : "OnFloor");
                    rows.Add((new RosterEntry(u.Id, name, dept, pk.ToString("hh:mm tt"), att.CheckOutTime?.ToPakistanTime().ToString("hh:mm tt"), status), att.CheckInTime));
                }
                else
                {
                    rows.Add((new RosterEntry(u.Id, name, dept, null, null, "Absent"), null));
                }
            }
            return rows.OrderBy(r => r.SortKey == null ? 1 : 0).ThenBy(r => r.SortKey).Select(r => r.Entry).ToList();
        }

        var attendanceByUser = todayEmployeeAttendance.ToDictionary(a => a.UserId);
        var roster = BuildRoster(attendanceByUser);

        // ----- Day-by-day breakdown for the selected period — empty for "day"
        // itself, since the live roster above already covers that one day.
        // Week/Month give the mobile dashboard a real per-day list (not just
        // aggregate charts), each day built from one shared batch query
        // rather than one query per day.
        var dailyBreakdown = new List<DayRosterDto>();
        if (period != "day")
        {
            var rangeAttendances = await _db.Attendances
                .Where(a => a.Date >= start && a.Date <= end && a.User!.Role == UserRole.Employee)
                .ToListAsync();
            var attendanceByDate = rangeAttendances.GroupBy(a => a.Date).ToDictionary(g => g.Key, g => g.ToDictionary(a => a.UserId));

            // Most recent day first — yesterday above the day before it, etc.
            for (var d = end; d >= start; d = d.AddDays(-1))
            {
                var dayAttendance = attendanceByDate.GetValueOrDefault(d) ?? new Dictionary<int, Attendance>();
                dailyBreakdown.Add(new DayRosterDto { Date = d, DateLabel = d.ToString("dddd, d MMM"), Roster = BuildRoster(dayAttendance) });
            }
        }

        return new DashboardAnalytics(
            weeklyHeadcount, arrivalCurve, presentOnTimeToday, lateToday, absentToday, shiftHealth,
            activeEmployeeCount, checkedInNow, awayCount,
            averageArrivalLabel, averageArrivalSublabel, averageArrivalTrendMinutes,
            reportsFiledRate, reportsFiledFraction, reportsFiledTrendPct,
            punctualityRatePct, punctualityRateTrendPct,
            roster, dailyBreakdown);
    }

    private static int TrendPct(double current, double previous)
    {
        if (previous == 0) return current == 0 ? 0 : 100;
        return (int)Math.Round((current - previous) / previous * 100);
    }

    private static (DateOnly Start, DateOnly End, DateOnly PrevStart, DateOnly PrevEnd) GetRange(string period, DateOnly today)
    {
        switch (period)
        {
            case "week":
            {
                var start = today.AddDays(-6);
                var prevEnd = start.AddDays(-1);
                var prevStart = prevEnd.AddDays(-6);
                return (start, today, prevStart, prevEnd);
            }
            case "month":
            {
                var start = today.AddDays(-29);
                var prevEnd = start.AddDays(-1);
                var prevStart = prevEnd.AddDays(-29);
                return (start, today, prevStart, prevEnd);
            }
            default:
            {
                var prevDay = today.AddDays(-1);
                return (today, today, prevDay, prevDay);
            }
        }
    }

    private record PeriodMetrics(double AvgArrivalMinutesFromShiftStart, int ReportsNum, int ReportsDenom, int PunctualityNum, int PunctualityDenom);

    private async Task<PeriodMetrics> ComputePeriodAsync(DateOnly start, DateOnly end)
    {
        var records = await _db.Attendances
            .Include(a => a.User)
            .Where(a => a.Date >= start && a.Date <= end && a.User!.Role == UserRole.Employee)
            .ToListAsync();
        return ComputePeriodFrom(records);
    }

    /// Same computation as ComputePeriodAsync, from records already loaded in
    /// memory — lets the "day" period (the default landing view) reuse
    /// ComputeAsync's own todayEmployeeAttendance fetch instead of firing the
    /// exact same query a second time.
    private static PeriodMetrics ComputePeriodFrom(List<Attendance> records)
    {
        // Relative to each record's OWN ShiftStartTime, not a fixed 9 AM — see
        // averageArrivalLabel's doc comment in ComputeAsync for why a single
        // company-wide anchor stopped meaning anything once Night shift
        // existed alongside Day shift.
        var avgArrivalMinutesFromShiftStart = records.Count == 0
            ? 0.0
            : records.Average(a =>
            {
                var pk = a.CheckInTime.ToPakistanTime();
                var shiftStart = a.User!.ShiftStartTime;
                return (pk.Hour * 60 + pk.Minute) - (shiftStart.Hour * 60 + shiftStart.Minute);
            });

        var reportsDenom = records.Count;
        var reportsNum = records.Count(a => a.ReportSubmitted);

        // Punctuality — Day/Night shift only (Internship/interns excluded, same
        // reasoning as ShiftHealth above), on-time rate among whoever actually
        // attended. Reuses `records` (already loaded with User/ShiftType) rather
        // than a separate query.
        var punctualityRecords = records.Where(a => a.User!.ShiftType != ShiftType.Internship).ToList();
        var punctualityDenom = punctualityRecords.Count;
        var punctualityNum = punctualityRecords.Count(a => !a.CheckInTime.IsLateFor(a.User!.ShiftStartTime));

        return new PeriodMetrics(avgArrivalMinutesFromShiftStart, reportsNum, reportsDenom, punctualityNum, punctualityDenom);
    }
}
