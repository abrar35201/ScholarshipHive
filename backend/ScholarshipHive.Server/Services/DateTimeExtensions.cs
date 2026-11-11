namespace ScholarshipHive.Server.Services;

public static class DateTimeExtensions
{
    // Pakistan Standard Time is a fixed UTC+5 offset with no daylight saving,
    // so this avoids depending on the host OS's timezone — which differs
    // between a local dev machine (was PKT) and the Railway container (UTC),
    // and is what caused displayed times to silently drift by 5 hours.
    private static readonly TimeSpan PakistanOffset = TimeSpan.FromHours(5);

    /// The attendance "day" rolls over at 7 AM Pakistan time, not midnight.
    /// Some employees work overnight shifts (e.g. 5 PM to 2 AM) — a plain
    /// midnight boundary would silently split one continuous shift into two
    /// attendance records the moment the clock ticks past 12:00 AM while
    /// they're still checked in, orphaning the first one (never checked out)
    /// and starting a second one that looks like they just arrived at
    /// midnight. 7 AM is comfortably past the latest shift-end this app
    /// needs to handle, so only the dead-of-night window actually shifts.
    private static readonly TimeSpan DayRolloverHour = TimeSpan.FromHours(7);

    public static DateTime ToPakistanTime(this DateTime utc) => utc.Add(PakistanOffset);

    /// The attendance business-day (see [DayRolloverHour]) a given UTC instant falls on,
    /// in Pakistan time — the general form PakistanToday() below is a special case of.
    public static DateOnly PakistanDateOf(DateTime utc) => DateOnly.FromDateTime(utc.ToPakistanTime() - DayRolloverHour);

    /// The current attendance business-day in Pakistan time — see
    /// [DayRolloverHour]. Use this instead of DateOnly.FromDateTime(DateTime.Now)
    /// for "what day is it" business logic (today's attendance, today's
    /// report, dashboard stats): the server itself runs in UTC, and a plain
    /// midnight boundary would also misattribute overnight shifts.
    public static DateOnly PakistanToday() => PakistanDateOf(DateTime.UtcNow);

    /// The UTC instant business day `d` starts at — 07:00 Pakistan time on `d`,
    /// which in UTC (PKT is a fixed UTC+5) is `d` 02:00 UTC — the exact inverse of
    /// [PakistanDateOf]. DateOnly.ToDateTime always produces Kind=Unspecified, which
    /// Npgsql rejects for a "timestamp with time zone" column, so this explicitly
    /// marks the result Utc.
    public static DateTime BusinessDayStartUtc(DateOnly d) =>
        DateTime.SpecifyKind(d.ToDateTime(TimeOnly.MinValue).AddHours(2), DateTimeKind.Utc);

    /// Minutes of grace after a shift's own start time before a check-in counts
    /// as "late" — under this, still "on time". Was previously a single fixed
    /// 9:15 AM cutoff (9:00 + this same 15-minute grace) for every employee
    /// regardless of what they actually work; now every employee has their own
    /// ShiftStartTime (see User.cs) and this grace applies relative to THAT.
    public const int LateGraceMinutes = 15;

    /// Whether a Pakistan-time check-in is late relative to a shift's own start
    /// time (plus [LateGraceMinutes]) — the one shared rule every "Late" badge
    /// and every late-count in the app computes from, so a shift-time change
    /// takes effect everywhere consistently instead of three independently
    /// hand-copied thresholds drifting apart.
    public static bool IsLateFor(this DateTime checkInUtc, TimeOnly shiftStart)
    {
        var pk = checkInUtc.ToPakistanTime();
        var checkInMinutes = pk.Hour * 60 + pk.Minute;
        var shiftStartMinutes = shiftStart.Hour * 60 + shiftStart.Minute;
        return checkInMinutes > shiftStartMinutes + LateGraceMinutes;
    }

    /// The company's work week is Monday–Saturday for everyone — EXCEPT
    /// Interns, whose work week is Monday–Friday (Saturday off too, same as
    /// Sunday for everyone). Every "is this a working day" check (attendance
    /// calendars, expected-attendance denominators in analytics) goes through
    /// this one place so a change here can never leave one department's
    /// calendar/rate calculations silently disagreeing with another's.
    public static bool IsWeekendOff(this DayOfWeek day, bool isIntern) =>
        isIntern ? day is DayOfWeek.Saturday or DayOfWeek.Sunday : day == DayOfWeek.Sunday;
}
