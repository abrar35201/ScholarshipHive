using System.Text;
using System.IO.Compression;
using System.Xml;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ScholarshipHive.Server.Data;
using ScholarshipHive.Server.Dtos;
using ScholarshipHive.Server.Models;
using ScholarshipHive.Server.Services;

namespace ScholarshipHive.Server.Controllers;

[Authorize(Policy = "AdminOnly")]
public class AttendanceController : Controller
{
    private readonly AppDbContext _db;
    private readonly AnalyticsService _analyticsService;

    public AttendanceController(AppDbContext db, AnalyticsService analyticsService)
    {
        _db = db;
        _analyticsService = analyticsService;
    }

    public async Task<IActionResult> Index(int? userId, DateTime? date, EmployeeDepartment? department, DateTime? fromDate, DateTime? toDate)
    {
        var employees = await _db.Users.Where(u => (u.Role != UserRole.Admin || u.Username.ToLower() != "admin")).OrderBy(u => u.Username).ToListAsync();
        ViewBag.Users = employees;
        ViewBag.SelectedUserId = userId;
        ViewBag.SelectedDate = date?.ToString("yyyy-MM-dd");
        ViewBag.SelectedDepartment = department;
        ViewBag.SelectedFromDate = fromDate?.ToString("yyyy-MM-dd");
        ViewBag.SelectedToDate = toDate?.ToString("yyyy-MM-dd");

        // A single-user calendar only makes sense once a specific person is
        // selected — "everyone, every day" doesn't collapse into one grid.
        if (userId.HasValue)
        {
            var selectedUser = employees.FirstOrDefault(u => u.Id == userId.Value);
            var selectedUserShiftStart = selectedUser?.ShiftStartTime ?? new TimeOnly(9, 30);
            var selectedUserIsIntern = selectedUser?.Department == EmployeeDepartment.Interns;
            var today = DateTimeExtensions.PakistanToday();
            // Defaulting to raw Pakistan clock time here (instead of the
            // business-day-aware `today` above) used to show tomorrow's date
            // as "today" for the whole 7 AM window after midnight — the
            // calendar's month/highlight would silently disagree with what
            // every other admin/mobile screen and the server itself consider
            // "today" until 7 AM caught up.
            var monthAnchor = date ?? today.ToDateTime(TimeOnly.MinValue);
            var monthStart = new DateOnly(monthAnchor.Year, monthAnchor.Month, 1);
            var daysInMonth = DateTime.DaysInMonth(monthAnchor.Year, monthAnchor.Month);

            var monthAttendance = await _db.Attendances
                .Where(a => a.UserId == userId.Value && a.Date >= monthStart && a.Date <= monthStart.AddDays(daysInMonth - 1))
                .ToListAsync();
            var byDate = monthAttendance.ToDictionary(a => a.Date);

            var calendar = new List<CalendarDay>();
            for (var d = 1; d <= daysInMonth; d++)
            {
                var day = new DateOnly(monthAnchor.Year, monthAnchor.Month, d);
                string status;
                if (day > today) status = "future";
                // A day off is a day off — but if this person still checked in
                // anyway, that's extra time worked, not just an ordinary
                // "present" day, and worth telling apart from a normal quiet
                // day off nobody worked. Saturday only counts as one for
                // Interns; everyone else's calendar treats it as a normal
                // working day.
                else if (day.DayOfWeek.IsWeekendOff(selectedUserIsIntern)) status = byDate.ContainsKey(day) ? "extra" : "weekend";
                else if (byDate.TryGetValue(day, out var att)) status = att.CheckInTime.IsLateFor(selectedUserShiftStart) ? "late" : "present";
                else status = "absent";
                calendar.Add(new CalendarDay(d, day, status));
            }
            ViewBag.Calendar = calendar;
            ViewBag.CalendarMonthLabel = monthAnchor.ToString("MMMM yyyy");

            // A From/To range (independent of the calendar's own month
            // navigation above) takes priority over the single-day filter —
            // lets an admin pull one person's complete attendance across
            // however wide a window they actually need, not just one day or
            // whatever month the calendar happens to be showing.
            var recordsQuery = _db.Attendances.Include(a => a.User).Where(a => a.UserId == userId.Value);
            if (fromDate.HasValue || toDate.HasValue)
            {
                var rangeStart = fromDate.HasValue ? DateOnly.FromDateTime(fromDate.Value) : DateOnly.MinValue;
                var rangeEnd = toDate.HasValue ? DateOnly.FromDateTime(toDate.Value) : DateOnly.MaxValue;
                recordsQuery = recordsQuery.Where(a => a.Date >= rangeStart && a.Date <= rangeEnd);
            }
            else if (date.HasValue)
            {
                recordsQuery = recordsQuery.Where(a => a.Date == DateOnly.FromDateTime(date.Value));
            }

            var records = await recordsQuery
                .OrderByDescending(a => a.Date).ThenByDescending(a => a.CheckInTime)
                .ToListAsync();
            return View(records);
        }

        // Office-wide mode — one calendar for everyone, a day at a time.
        var today2 = DateTimeExtensions.PakistanToday();
        var selectedDateOnly = date.HasValue ? DateOnly.FromDateTime(date.Value) : today2;
        var (officeCalendar, monthLabel, dayRoster, activeCount) = await _analyticsService.ComputeOfficeAttendanceAsync(selectedDateOnly, department, employees);

        ViewBag.OfficeCalendar = officeCalendar;
        ViewBag.OfficeMonthLabel = monthLabel;
        ViewBag.SelectedDateOnly = selectedDateOnly;
        ViewBag.DayRoster = dayRoster;
        ViewBag.ActiveEmployeeCount = activeCount;
        return View(new List<Attendance>());
    }

    public async Task<IActionResult> ExportCsv(DateTime date, EmployeeDepartment? department)
    {
        var day = DateOnly.FromDateTime(date);
        var employees = await _db.Users.Where(u => (u.Role != UserRole.Admin || u.Username.ToLower() != "admin")).OrderBy(u => u.Username).ToListAsync();
        var (_, _, dayRoster, _) = await _analyticsService.ComputeOfficeAttendanceAsync(day, department, employees);

        var sb = new StringBuilder();
        sb.AppendLine("Name,Department,CheckIn,CheckOut,Duration,Status");
        foreach (var r in dayRoster)
        {
            sb.AppendLine($"\"{r.Name.Replace("\"", "'")}\",{r.Department},{r.CheckInLabel},{r.CheckOutLabel},{r.DurationLabel},{r.Status}");
        }
        var bytes = Encoding.UTF8.GetBytes(sb.ToString());
        return File(bytes, "text/csv", $"attendance-{day:yyyy-MM-dd}.csv");
    }

    public async Task<IActionResult> ExportExcel(DateTime date, EmployeeDepartment? department)
    {
        var day = DateOnly.FromDateTime(date);
        var rows = await GetAttendanceExportRowsAsync(day, department);
        var bytes = CreateAttendanceWorkbook(rows);
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", $"attendance-{day:yyyy-MM-dd}.xlsx");
    }

    public async Task<IActionResult> ExportEmployeeExcelsZip(DateTime date, EmployeeDepartment? department)
    {
        var day = DateOnly.FromDateTime(date);
        var rows = await GetAttendanceExportRowsAsync(day, department);
        using var stream = new MemoryStream();
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
        {
            foreach (var row in rows.Where(r => r.HasAttendance).OrderBy(r => r.Username, StringComparer.OrdinalIgnoreCase))
            {
                var entry = archive.CreateEntry($"{SafeFileName(row.Username)}-{row.UserId}.xlsx", CompressionLevel.Optimal);
                await using var entryStream = entry.Open();
                var workbook = CreateAttendanceWorkbook(new[] { row });
                await entryStream.WriteAsync(workbook);
            }
        }

        return File(stream.ToArray(), "application/zip", $"attendance-employees-{day:yyyy-MM-dd}.zip");
    }

    private async Task<List<AttendanceExportRow>> GetAttendanceExportRowsAsync(DateOnly day, EmployeeDepartment? department)
    {
        var employees = await _db.Users.Where(u => (u.Role != UserRole.Admin || u.Username.ToLower() != "admin")).OrderBy(u => u.Username).ToListAsync();
        var (_, _, dayRoster, _) = await _analyticsService.ComputeOfficeAttendanceAsync(day, department, employees);
        var employeesById = employees.ToDictionary(u => u.Id);

        return dayRoster.Select(row => new AttendanceExportRow(
            row.UserId,
            row.Name,
            employeesById[row.UserId].Username,
            row.Department,
            day.ToString("yyyy-MM-dd"),
            row.CheckInLabel ?? string.Empty,
            row.CheckOutLabel ?? string.Empty,
            row.DurationLabel ?? string.Empty,
            row.Status,
            row.CheckInLabel != null)).ToList();
    }

    private static byte[] CreateAttendanceWorkbook(IReadOnlyList<AttendanceExportRow> rows)
    {
        const string spreadsheetNs = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        const string relationshipNs = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
        const string packageRelationshipNs = "http://schemas.openxmlformats.org/package/2006/relationships";
        const string contentTypesNs = "http://schemas.openxmlformats.org/package/2006/content-types";
        using var stream = new MemoryStream();
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
        {
            WriteXmlEntry(archive, "[Content_Types].xml", writer =>
            {
                writer.WriteStartElement("Types", contentTypesNs);
                writer.WriteStartElement("Default", contentTypesNs);
                writer.WriteAttributeString("Extension", "rels");
                writer.WriteAttributeString("ContentType", "application/vnd.openxmlformats-package.relationships+xml");
                writer.WriteEndElement();
                writer.WriteStartElement("Default", contentTypesNs);
                writer.WriteAttributeString("Extension", "xml");
                writer.WriteAttributeString("ContentType", "application/xml");
                writer.WriteEndElement();
                writer.WriteStartElement("Override", contentTypesNs);
                writer.WriteAttributeString("PartName", "/xl/workbook.xml");
                writer.WriteAttributeString("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml");
                writer.WriteEndElement();
                writer.WriteStartElement("Override", contentTypesNs);
                writer.WriteAttributeString("PartName", "/xl/worksheets/sheet1.xml");
                writer.WriteAttributeString("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml");
                writer.WriteEndElement();
                writer.WriteEndElement();
            });
            WriteXmlEntry(archive, "_rels/.rels", writer =>
            {
                writer.WriteStartElement("Relationships", packageRelationshipNs);
                writer.WriteStartElement("Relationship", packageRelationshipNs);
                writer.WriteAttributeString("Id", "rId1");
                writer.WriteAttributeString("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument");
                writer.WriteAttributeString("Target", "xl/workbook.xml");
                writer.WriteEndElement();
                writer.WriteEndElement();
            });
            WriteXmlEntry(archive, "xl/workbook.xml", writer =>
            {
                writer.WriteStartElement("workbook", spreadsheetNs);
                writer.WriteAttributeString("xmlns", "r", null, relationshipNs);
                writer.WriteStartElement("sheets", spreadsheetNs);
                writer.WriteStartElement("sheet", spreadsheetNs);
                writer.WriteAttributeString("name", "Attendance");
                writer.WriteAttributeString("sheetId", "1");
                writer.WriteAttributeString("r", "id", relationshipNs, "rId1");
                writer.WriteEndElement();
                writer.WriteEndElement();
                writer.WriteEndElement();
            });
            WriteXmlEntry(archive, "xl/_rels/workbook.xml.rels", writer =>
            {
                writer.WriteStartElement("Relationships", packageRelationshipNs);
                writer.WriteStartElement("Relationship", packageRelationshipNs);
                writer.WriteAttributeString("Id", "rId1");
                writer.WriteAttributeString("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet");
                writer.WriteAttributeString("Target", "worksheets/sheet1.xml");
                writer.WriteEndElement();
                writer.WriteEndElement();
            });
            WriteXmlEntry(archive, "xl/worksheets/sheet1.xml", writer =>
            {
                writer.WriteStartElement("worksheet", spreadsheetNs);
                writer.WriteStartElement("sheetData", spreadsheetNs);
                var headings = new[] { "Employee Name", "Username", "Department", "Date", "Check In", "Check Out", "Total Working Hours", "Status" };
                WriteWorksheetRow(writer, headings, 1, spreadsheetNs);
                for (var i = 0; i < rows.Count; i++)
                {
                    WriteWorksheetRow(writer, rows[i].Values, i + 2, spreadsheetNs);
                }
                writer.WriteEndElement();
                writer.WriteEndElement();
            });
        }

        return stream.ToArray();
    }

    private static void WriteXmlEntry(ZipArchive archive, string path, Action<XmlWriter> writeContent)
    {
        var entry = archive.CreateEntry(path, CompressionLevel.Optimal);
        using var entryStream = entry.Open();
        using var writer = XmlWriter.Create(entryStream, new XmlWriterSettings { Encoding = new UTF8Encoding(false), CloseOutput = false });
        writer.WriteStartDocument();
        writeContent(writer);
        writer.WriteEndDocument();
    }

    private static void WriteWorksheetRow(XmlWriter writer, IReadOnlyList<string> values, int rowNumber, string spreadsheetNs)
    {
        writer.WriteStartElement("row", spreadsheetNs);
        writer.WriteAttributeString("r", rowNumber.ToString());
        for (var column = 0; column < values.Count; column++)
        {
            writer.WriteStartElement("c", spreadsheetNs);
            writer.WriteAttributeString("r", $"{(char)('A' + column)}{rowNumber}");
            writer.WriteAttributeString("t", "inlineStr");
            writer.WriteStartElement("is", spreadsheetNs);
            writer.WriteStartElement("t", spreadsheetNs);
            writer.WriteString(values[column] ?? string.Empty);
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndElement();
        }
        writer.WriteEndElement();
    }

    private static string SafeFileName(string value)
    {
        const string invalid = "<>:\"/\\|?*";
        var safe = new string(value.Select(c => invalid.Contains(c) || char.IsControl(c) ? '_' : c).ToArray()).Trim().Trim('.');
        return string.IsNullOrWhiteSpace(safe) ? "employee" : safe;
    }

    private sealed record AttendanceExportRow(
        int UserId,
        string Name,
        string Username,
        string Department,
        string Date,
        string CheckIn,
        string CheckOut,
        string Duration,
        string Status,
        bool HasAttendance)
    {
        public string[] Values => [Name, Username, Department, Date, CheckIn, CheckOut, Duration, Status];
    }
}
