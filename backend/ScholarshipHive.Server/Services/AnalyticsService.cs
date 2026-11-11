using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;

namespace ScholarshipHive.Server.Services;

public record StatusSplit(int PresentPct, int LatePct, int AbsentPct, int Present, int Late, int Absent);
public record DeptHealthRate(string Department, int RatePct, int ReportsLast30d);
public record InsightCard(string Title, string Body, string Tone);
public record AnalyticsData(StatusSplit Status, List<DeptHealthRate> DepartmentHealth, List<InsightCard> Insights);

/// Rate/reports/punctuality for one active employee, last 30 working days —
/// shared by the web Team page (Users/Index) and the mobile Team tab.
public record TeamMetricsEntry(int UserId, int RatePct, int Reports, int Leads, int PunctualityPct, string Status);

/// Powers the Analytics page — everything here is computed from the last 30
/// days of real attendance/report rows, nothing decorative or hardcoded.
/// Saturday counts as a working day for everyone except Interns, who also
/// have it off (see DateTimeExtensions.IsWeekendOff) — every expected-
/// attendance calculation below excludes only each person's own actual
/// non-working days, not a single company-wide weekend.
public class AnalyticsService
{
    private readonly AppDbContext _db;

    public AnalyticsService(AppDbContext db)
    {
        _db = db;
    }

    private static bool IsIntern(User u) => u.Department == EmployeeDepartment.Interns;

    /// Working days in [from, to] for one department — Interns have fewer of
    /// them (Saturday off too), so this can no longer be a single shared count
    /// applied uniformly to every employee/department.
    private static int CountWorkingDays(DateOnly from, DateOnly to, bool isIntern)
    {
        var count = 0;
        for (var d = from; d <= to; d = d.AddDays(1))
        {
            if (!d.DayOfWeek.IsWeekendOff(isIntern)) count++;
        }
        return count;
    }

    /// The later of `windowStart` and the business day this person actually
    /// joined on — someone hired 5 days ago was never "expected" to have
    /// attended on any of the 25 days before that. Counting from a shared
    /// `windowStart` for everyone made every recent hire's own rate (and their
    /// department's/shift's blended rate) look far worse than reality — e.g. a
    /// employee joined day before yesterday, was there twice, sitting at
    /// ~7% instead of the ~100% their own two actual working days deserved.
    ///
    /// `earliestAttendance` (that user's own earliest Attendance.Date already
    /// loaded in the current 30-day window, if any) is folded in as a floor:
    /// User.CreatedAt is NOT reliable for anyone carried over from the old
    /// Railway account migration — those rows were re-inserted with a fresh
    /// CreatedAt at COPY time, not their real original signup date, while
    /// their Attendance history correctly kept its true original dates. That
    /// mismatch (CreatedAt reading days AFTER attendance that genuinely
    /// happened) was silently shrinking `expected` far below `attended` and
    /// pushing rates past 100%. A real attendance row earlier than CreatedAt
    /// is proof the person was already active then regardless of what
    /// CreatedAt claims, so it wins.
    private static DateOnly EffectiveStart(User u, DateOnly windowStart, DateOnly? earliestAttendance = null)
    {
        var joined = DateTimeExtensions.PakistanDateOf(u.CreatedAt);
        if (earliestAttendance.HasValue && earliestAttendance.Value < joined) joined = earliestAttendance.Value;
        return joined > windowStart ? joined : windowStart;
    }

    public async Task<AnalyticsData> ComputeAsync()
    {
        var today = DateTimeExtensions.PakistanToday();
        var monthStart = today.AddDays(-29);

        // A self-registered account not yet approved by an admin cannot check
        // in at all (see AuthController.Login/Checkin) — counting it as
        // "expected to attend" made every pending signup show up as a
        // permanent, unavoidable absence dragging every rate down until
        // someone got around to approving them.
        var employees = await _db.Users.Where(u => u.IsActive && u.IsApproved && u.Role == UserRole.Employee).ToListAsync();
        var monthAttendance = await _db.Attendances
            .Where(a => a.Date >= monthStart && a.Date <= today)
            .Include(a => a.User)
            .ToListAsync();
        var byUserDate = monthAttendance.ToDictionary(a => (a.UserId, a.Date));
        var earliestAttendanceByUser = monthAttendance
            .GroupBy(a => a.UserId)
            .ToDictionary(g => g.Key, g => g.Min(a => a.Date));

        int present = 0, late = 0, absent = 0;
        var absencesByWeekday = new Dictionary<DayOfWeek, int>();
        var expectedByWeekday = new Dictionary<DayOfWeek, int>();

        foreach (var u in employees)
        {
            var isIntern = IsIntern(u);
            DateOnly? earliestForUser = earliestAttendanceByUser.TryGetValue(u.Id, out var ea) ? ea : null;
            var effectiveStart = EffectiveStart(u, monthStart, earliestForUser);
            for (var d = effectiveStart; d <= today; d = d.AddDays(1))
            {
                if (d.DayOfWeek.IsWeekendOff(isIntern)) continue;

                expectedByWeekday[d.DayOfWeek] = expectedByWeekday.GetValueOrDefault(d.DayOfWeek) + 1;
                if (byUserDate.TryGetValue((u.Id, d), out var att))
                {
                    if (att.CheckInTime.IsLateFor(u.ShiftStartTime)) late++;
                    else present++;
                }
                else
                {
                    absent++;
                    absencesByWeekday[d.DayOfWeek] = absencesByWeekday.GetValueOrDefault(d.DayOfWeek) + 1;
                }
            }
        }

        var total = Math.Max(present + late + absent, 1);
        var status = new StatusSplit(
            present * 100 / total, late * 100 / total, absent * 100 / total,
            present, late, absent);

        // Department health — attendance rate over the same 30 days (each
        // employee's own working-day count from their own join date — see
        // EffectiveStart/CountWorkingDays), plus how many reports each
        // department actually filed in that window.
        var deptGroups = employees.GroupBy(u => u.Department).ToList();
        var departmentHealth = new List<DeptHealthRate>();
        foreach (var g in deptGroups)
        {
            var dept = g.Key;
            var deptIds = g.Select(u => u.Id).ToHashSet();
            var isDeptIntern = dept == EmployeeDepartment.Interns;
            var expected = g.Sum(u =>
            {
                DateOnly? earliest = earliestAttendanceByUser.TryGetValue(u.Id, out var ea) ? ea : null;
                return CountWorkingDays(EffectiveStart(u, monthStart, earliest), today, isDeptIntern);
            });
            var attended = monthAttendance.Count(a => deptIds.Contains(a.UserId));
            // Clamped to 100 as a backstop only (e.g. someone genuinely
            // attending on their own day off) — EffectiveStart's earliest-
            // attendance floor above is what actually keeps this honest.
            var rate = expected > 0 ? Math.Min(attended * 100 / expected, 100) : 0;
            var reportsCount = monthAttendance.Count(a => deptIds.Contains(a.UserId) && a.ReportSubmitted);
            departmentHealth.Add(new DeptHealthRate(dept.ToString(), rate, reportsCount));
        }

        var insights = await BuildInsightsAsync(monthStart, today, absencesByWeekday, expectedByWeekday, departmentHealth);

        return new AnalyticsData(status, departmentHealth, insights);
    }

    private async Task<List<InsightCard>> BuildInsightsAsync(
        DateOnly monthStart, DateOnly today,
        Dictionary<DayOfWeek, int> absencesByWeekday, Dictionary<DayOfWeek, int> expectedByWeekday,
        List<DeptHealthRate> departmentHealth)
    {
        var insights = new List<InsightCard>();

        // Card 1 — which weekday absences cluster on.
        if (expectedByWeekday.Values.Sum() >= 10)
        {
            var worst = expectedByWeekday.Keys
                .Select(day => (Day: day, Rate: expectedByWeekday[day] > 0 ? absencesByWeekday.GetValueOrDefault(day) * 100.0 / expectedByWeekday[day] : 0))
                .OrderByDescending(x => x.Rate)
                .First();
            var overallAbsentPct = expectedByWeekday.Values.Sum() > 0
                ? absencesByWeekday.Values.Sum() * 100.0 / expectedByWeekday.Values.Sum() : 0;
            insights.Add(worst.Rate > 0
                ? new InsightCard($"{worst.Day}s run thin", $"{Math.Round(worst.Rate)}% absence rate on {worst.Day}s over the last 30 days, versus {Math.Round(overallAbsentPct)}% overall.", "warn")
                : new InsightCard("Attendance is steady", "No single weekday stands out for absences over the last 30 days.", "warn"));
        }
        else
        {
            insights.Add(new InsightCard("Not enough data yet", "Come back after a few more weeks of attendance to see weekday patterns.", "warn"));
        }

        // Card 2 — how late reports get filed relative to checkout.
        var reportsWithCheckout = await _db.Reports
            .Include(r => r.Attendance)
            .Where(r => r.Attendance!.Date >= monthStart && r.Attendance.Date <= today && r.Attendance.CheckOutTime != null)
            .Select(r => new { r.SubmittedAt, CheckOutTime = r.Attendance!.CheckOutTime!.Value })
            .ToListAsync();
        if (reportsWithCheckout.Count >= 5)
        {
            var slipCount = reportsWithCheckout.Count(r => (r.SubmittedAt - r.CheckOutTime).TotalMinutes > 15);
            var slipPct = Math.Round(slipCount * 100.0 / reportsWithCheckout.Count);
            insights.Add(slipCount > 0
                ? new InsightCard("Reports slip after checkout", $"{slipPct}% of filed reports are submitted more than 15 minutes after checkout ({slipCount} of {reportsWithCheckout.Count}).", "alt")
                : new InsightCard("Reports file on time", "Every report in the last 30 days was filed within 15 minutes of checkout.", "alt"));
        }
        else
        {
            insights.Add(new InsightCard("Not enough report data yet", "Need a few more filed reports to see filing-time patterns.", "alt"));
        }

        // Card 3 — early check-in vs leads closed, Day-shift Calling only (the
        // only department whose reports carry a lead count). Restricted to Day
        // shift and measured relative to each person's OWN ShiftStartTime —
        // used to be two fixed clock cutoffs (before 8:45 / at-or-after 9:30)
        // applied to every Calling employee regardless of shift, which silently
        // dumped every Night-shift agent's evening check-in (any time from
        // 6 PM onward is ">= 9:30") into the "late" bucket alongside genuinely
        // late Day-shift arrivals, and no longer even lined up with Day shift's
        // own actual start time once that moved to 9:30 AM.
        var callingReports = await _db.Reports
            .Include(r => r.Attendance)
            .Include(r => r.User)
            .Where(r => r.Attendance!.Date >= monthStart && r.Attendance.Date <= today
                && r.User!.Department == EmployeeDepartment.Calling && r.User.ShiftType == ShiftType.Day)
            .Select(r => new { r.NewLeads, CheckInTime = r.Attendance!.CheckInTime, ShiftStart = r.User!.ShiftStartTime })
            .ToListAsync();
        bool CheckedInEarly(TimeOnly shiftStart, DateTime checkInUtc)
        {
            var pk = checkInUtc.ToPakistanTime();
            var checkInMinutes = pk.Hour * 60 + pk.Minute;
            var shiftStartMinutes = shiftStart.Hour * 60 + shiftStart.Minute;
            return checkInMinutes <= shiftStartMinutes - 15;
        }
        var early = callingReports.Where(r => CheckedInEarly(r.ShiftStart, r.CheckInTime)).ToList();
        var late = callingReports.Where(r => r.CheckInTime.IsLateFor(r.ShiftStart)).ToList();
        if (early.Count >= 3 && late.Count >= 3)
        {
            var earlyAvg = early.Average(r => r.NewLeads);
            var lateAvg = late.Average(r => r.NewLeads);
            var diffPct = lateAvg > 0 ? Math.Round((earlyAvg - lateAvg) / lateAvg * 100) : 0;
            insights.Add(diffPct > 0
                ? new InsightCard("Early starts close more", $"Day-shift Calling staff who check in 15+ minutes before their own shift start handle {diffPct}% more leads on average than those who check in late.", "ok")
                : new InsightCard("Arrival time isn't the driver", "No meaningful gap between early and late arrivals in leads handled this month.", "ok"));
        }
        else
        {
            var best = departmentHealth.OrderByDescending(d => d.RatePct).FirstOrDefault();
            insights.Add(best != null
                ? new InsightCard("Best attendance this month", $"{best.Department} leads at {best.RatePct}% attendance over the last 30 days.", "ok")
                : new InsightCard("Not enough data yet", "Check back once more shifts and reports have been logged.", "ok"));
        }

        return insights;
    }

    /// Same 30-working-day window as ComputeAsync, but per person instead of
    /// aggregated — powers the Team page/tab's metric cards.
    public async Task<Dictionary<int, TeamMetricsEntry>> ComputeTeamMetricsAsync(List<User> users)
    {
        var today = DateTimeExtensions.PakistanToday();
        var monthStart = today.AddDays(-29);

        var monthAttendance = await _db.Attendances
            .Where(a => a.Date >= monthStart && a.Date <= today)
            .ToListAsync();
        var todayByUser = monthAttendance.Where(a => a.Date == today).ToDictionary(a => a.UserId);
        var leadsByUser = await _db.Reports
            .Include(r => r.Attendance)
            .Where(r => r.Attendance!.Date >= monthStart && r.Attendance.Date <= today)
            .GroupBy(r => r.UserId)
            .Select(g => new { UserId = g.Key, Leads = g.Sum(r => r.NewLeads) })
            .ToDictionaryAsync(x => x.UserId, x => x.Leads);

        var metrics = new Dictionary<int, TeamMetricsEntry>();
        // Unapproved (pending) accounts can't check in at all yet — see
        // AnalyticsService.ComputeAsync's EffectiveStart doc comment — so
        // they get no metrics entry rather than a misleading near-0% rate.
        foreach (var u in users.Where(u => u.Role == UserRole.Employee && u.IsApproved))
        {
            var own = monthAttendance.Where(a => a.UserId == u.Id).ToList();
            var attended = own.Count;
            var lateCount = own.Count(a => a.CheckInTime.IsLateFor(u.ShiftStartTime));
            DateOnly? earliestForUser = own.Count > 0 ? own.Min(a => a.Date) : null;
            var workingDays = CountWorkingDays(EffectiveStart(u, monthStart, earliestForUser), today, IsIntern(u));
            // Clamped to 100 as a backstop only (e.g. someone genuinely
            // attending on their own day off adds to `attended` without a
            // matching working day) — EffectiveStart above is what actually
            // keeps this honest in the normal case.
            var ratePct = workingDays > 0 ? Math.Min(attended * 100 / workingDays, 100) : 0;
            // 0, not 100, when there's no attendance at all to judge punctuality
            // from — see DashboardAnalyticsService's ShiftHealth punctuality for
            // the same reasoning.
            var punctualityPct = attended > 0 ? (attended - lateCount) * 100 / attended : 0;
            var reportsCount = own.Count(a => a.ReportSubmitted);
            var leads = leadsByUser.GetValueOrDefault(u.Id, 0);

            string status;
            if (todayByUser.TryGetValue(u.Id, out var att))
            {
                status = att.CheckInTime.IsLateFor(u.ShiftStartTime) ? "Late" : (att.CheckOutTime != null ? "CheckedOut" : "OnFloor");
            }
            else
            {
                status = "Absent";
            }

            metrics[u.Id] = new TeamMetricsEntry(u.Id, ratePct, reportsCount, leads, punctualityPct, status);
        }
        return metrics;
    }

    /// Office-wide attendance calendar (one dot per day, majority-status-wins
    /// among active employees) plus the full roster log for one selected day
    /// — shared by the web Attendance page's office-wide mode and the mobile
    /// Attendance tab.
    public async Task<(List<CalendarDay> Calendar, string MonthLabel, List<AttendanceRosterRow> DayRoster, int ActiveCount)> ComputeOfficeAttendanceAsync(
        DateOnly selectedDate, EmployeeDepartment? department, List<User> employees)
    {
        var today = DateTimeExtensions.PakistanToday();
        var monthStart = new DateOnly(selectedDate.Year, selectedDate.Month, 1);
        var daysInMonth = DateTime.DaysInMonth(selectedDate.Year, selectedDate.Month);

        // Unapproved (pending) accounts can't check in yet — leaving them in
        // would show them as permanently "Absent" on every day rather than
        // simply not-yet-active.
        var activeEmployeeIds = employees.Where(u => u.IsActive && u.IsApproved).Select(u => u.Id).ToHashSet();
        var shiftStartByUserId = employees.ToDictionary(u => u.Id, u => u.ShiftStartTime);
        var monthAttendance = await _db.Attendances
            .Where(a => a.Date >= monthStart && a.Date <= monthStart.AddDays(daysInMonth - 1) && activeEmployeeIds.Contains(a.UserId))
            .ToListAsync();
        var byDate = monthAttendance.GroupBy(a => a.Date).ToDictionary(g => g.Key, g => g.ToList());

        // The calendar itself isn't filtered to one department (the roster
        // below is) — its own weekend rule follows whichever department is
        // selected, or defaults to the majority rule (only Sunday off) for
        // the combined "All" view, since Interns are the one exception rather
        // than the norm.
        var calendarIsIntern = department == EmployeeDepartment.Interns;

        var calendar = new List<CalendarDay>();
        for (var d = 1; d <= daysInMonth; d++)
        {
            var day = new DateOnly(selectedDate.Year, selectedDate.Month, d);
            string status;
            if (day > today) status = "future";
            else if (day.DayOfWeek.IsWeekendOff(calendarIsIntern))
            {
                // A weekend is a day off, not a day someone can be "absent"
                // from — but if anyone actually came in anyway, that's worth
                // surfacing as its own thing rather than looking identical to
                // an ordinary quiet Saturday nobody worked.
                status = (byDate.GetValueOrDefault(day)?.Count ?? 0) > 0 ? "extra" : "weekend";
            }
            else
            {
                // Used to be "one absence marks the whole day absent" — with any
                // real headcount beyond a handful of people, someone is *always*
                // missing on any given day, which made Present/Late permanently
                // unreachable no matter how well everyone else did. Whichever
                // bucket most active employees actually fall into for the day is
                // what the dot (and the Present/Late/Absent counts below the
                // calendar) reflects instead — on-time attendance ties break in
                // its favor, then late, then absent.
                var dayRecords = byDate.GetValueOrDefault(day) ?? new List<Attendance>();
                var attendedIds = dayRecords.Select(a => a.UserId).ToHashSet();
                var absentCount = activeEmployeeIds.Except(attendedIds).Count();
                var lateCount = dayRecords.Count(a => a.CheckInTime.IsLateFor(shiftStartByUserId.GetValueOrDefault(a.UserId, new TimeOnly(9, 30))));
                var presentCount = dayRecords.Count - lateCount;
                status = (presentCount >= lateCount && presentCount >= absentCount) ? "present"
                    : (lateCount >= absentCount) ? "late"
                    : "absent";
            }
            calendar.Add(new CalendarDay(d, day, status));
        }

        var dayRecordsForRoster = byDate.GetValueOrDefault(selectedDate) ?? new List<Attendance>();
        var attByUser = dayRecordsForRoster.ToDictionary(a => a.UserId);
        var rosterUsers = employees.Where(u => u.IsActive && u.IsApproved && (department == null || u.Department == department));

        // Sort by the real CheckInTime, not the formatted label — "hh:mm tt"
        // strings don't sort chronologically as plain text (12-hour labels put
        // every PM time before 09/10/11 AM), unlike the old 24-hour labels.
        var dayRosterWithKey = new List<(AttendanceRosterRow Row, DateTime? SortKey)>();
        foreach (var u in rosterUsers)
        {
            var name = u.FullName?.Length > 0 ? u.FullName : u.Username;
            if (attByUser.TryGetValue(u.Id, out var att))
            {
                var pkIn = att.CheckInTime.ToPakistanTime();
                var status = att.CheckInTime.IsLateFor(u.ShiftStartTime) ? "Late" : (att.CheckOutTime != null ? "CheckedOut" : "OnFloor");
                string? durationLabel = null;
                if (att.CheckOutTime is { } outTime)
                {
                    var span = outTime - att.CheckInTime;
                    durationLabel = span.TotalHours > 16 || span.TotalMinutes < 0
                        ? "Review checkout"
                        : $"{(int)span.TotalHours}h {span.Minutes}m";
                }
                dayRosterWithKey.Add((new AttendanceRosterRow(u.Id, name, u.Department.ToString(), pkIn.ToString("hh:mm tt"),
                    att.CheckOutTime?.ToPakistanTime().ToString("hh:mm tt"), durationLabel, status), att.CheckInTime));
            }
            else
            {
                // Nobody was expected in on a day off — showing every
                // non-attendee as "Absent" on a day off would count the whole
                // roster as absent then, when there was nothing to be absent
                // FROM in the first place. Per THIS user's own department —
                // Saturday is a day off for Interns but an ordinary working
                // day for everyone else.
                var offDayStatus = selectedDate.DayOfWeek.IsWeekendOff(u.Department == EmployeeDepartment.Interns) ? "Off" : "Absent";
                dayRosterWithKey.Add((new AttendanceRosterRow(u.Id, name, u.Department.ToString(), null, null, null, offDayStatus), null));
            }
        }
        var dayRoster = dayRosterWithKey.OrderBy(r => r.SortKey == null ? 1 : 0).ThenBy(r => r.SortKey).Select(r => r.Row).ToList();

        return (calendar, monthStart.ToString("MMMM yyyy"), dayRoster, activeEmployeeIds.Count);
    }
}
