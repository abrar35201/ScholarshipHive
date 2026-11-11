namespace ScholarshipHive.Server.Dtos;

/// One row of the admin Hours list — a person's total real accumulated presence
/// (see AttendanceDurationService) across whatever date range is currently selected.
public class HoursListEntryDto
{
    public int UserId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int TotalMinutes { get; set; }
    public int GapMinutes { get; set; }
}

public class HoursDayDto
{
    public DateOnly Date { get; set; }
    public int Minutes { get; set; }
    public int GapMinutes { get; set; }

    /// True on "today" while the person is still checked in — the day's total is
    /// still growing, not a final figure.
    public bool StillOpen { get; set; }
}

/// One person's day-by-day breakdown, reached by tapping their row in the Hours list.
public class HoursDetailDto
{
    public int UserId { get; set; }
    public string Name { get; set; } = string.Empty;
    public int TotalMinutes { get; set; }
    public int TotalGapMinutes { get; set; }
    public List<HoursDayDto> Days { get; set; } = new();
}
