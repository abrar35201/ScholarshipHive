import 'report.dart' show ReportFileRef;

class ChartPoint {
  final String label;
  final double value;
  ChartPoint({required this.label, required this.value});
  factory ChartPoint.fromJson(Map<String, dynamic> json) => ChartPoint(
    label: json['label'] as String,
    value: (json['value'] as num).toDouble(),
  );
}

/// One shift type's genuine attendance health, last 30 days — Day and Night
/// only. Internship shift (the interns) is deliberately excluded — they run a
/// fundamentally shorter, different daily window, so mixing them in would just
/// water down what the regular workforce's numbers actually mean.
class ShiftHealth {
  final String shiftLabel;
  final int presentToday;
  final int activeEmployees;
  final int attendanceRatePct30d;
  final int punctualityRatePct30d;
  ShiftHealth({
    required this.shiftLabel,
    required this.presentToday,
    required this.activeEmployees,
    required this.attendanceRatePct30d,
    required this.punctualityRatePct30d,
  });
  factory ShiftHealth.fromJson(Map<String, dynamic> json) => ShiftHealth(
    shiftLabel: json['shiftLabel'] as String,
    presentToday: json['presentToday'] as int,
    activeEmployees: json['activeEmployees'] as int,
    attendanceRatePct30d: json['attendanceRatePct30d'] as int,
    punctualityRatePct30d: json['punctualityRatePct30d'] as int,
  );
}

class RosterEntry {
  final int userId;
  final String name;
  final String department;
  final String? checkInLabel;
  final String? checkOutLabel;
  final String status;

  RosterEntry({
    required this.userId,
    required this.name,
    required this.department,
    required this.checkInLabel,
    required this.checkOutLabel,
    required this.status,
  });

  factory RosterEntry.fromJson(Map<String, dynamic> json) => RosterEntry(
    userId: json['userId'] as int,
    name: json['name'] as String,
    department: json['department'] as String,
    checkInLabel: json['checkInLabel'] as String?,
    checkOutLabel: json['checkOutLabel'] as String?,
    status: json['status'] as String,
  );
}

class DayRoster {
  final String date;
  final String dateLabel;
  final List<RosterEntry> roster;

  DayRoster({
    required this.date,
    required this.dateLabel,
    required this.roster,
  });

  factory DayRoster.fromJson(Map<String, dynamic> json) => DayRoster(
    date: json['date'] as String,
    dateLabel: json['dateLabel'] as String,
    roster: ((json['roster'] as List?) ?? [])
        .map((e) => RosterEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class AdminDashboard {
  final int totalUsers;
  final int checkedInNow;
  final int reportsToday;
  final int configuredRouters;
  final int pendingApprovals;
  final int pendingNetworks;
  final List<ChartPoint> weeklyHeadcount;
  final List<ChartPoint> arrivalCurve;
  final int presentOnTimeToday;
  final int lateToday;
  final int absentToday;
  final List<ShiftHealth> shiftHealth;
  final int totalActiveEmployees;
  final int awayCount;
  final String averageArrivalLabel;
  final String averageArrivalSublabel;
  final int averageArrivalTrendMinutes;
  final int reportsFiledRate;
  final String reportsFiledFraction;
  final int reportsFiledTrendPct;
  final int punctualityRatePct;
  final int punctualityRateTrendPct;
  final List<RosterEntry> roster;
  final List<DayRoster> dailyBreakdown;
  final bool pushNotificationsEnabled;

  AdminDashboard({
    required this.totalUsers,
    required this.checkedInNow,
    required this.reportsToday,
    required this.configuredRouters,
    required this.pendingApprovals,
    required this.pendingNetworks,
    required this.weeklyHeadcount,
    required this.arrivalCurve,
    required this.presentOnTimeToday,
    required this.lateToday,
    required this.absentToday,
    required this.shiftHealth,
    required this.totalActiveEmployees,
    required this.awayCount,
    required this.averageArrivalLabel,
    required this.averageArrivalSublabel,
    required this.averageArrivalTrendMinutes,
    required this.reportsFiledRate,
    required this.reportsFiledFraction,
    required this.reportsFiledTrendPct,
    required this.punctualityRatePct,
    required this.punctualityRateTrendPct,
    required this.roster,
    required this.dailyBreakdown,
    this.pushNotificationsEnabled = true,
  });

  factory AdminDashboard.fromJson(Map<String, dynamic> json) => AdminDashboard(
    totalUsers: json['totalUsers'] as int,
    checkedInNow: json['checkedInNow'] as int,
    reportsToday: json['reportsToday'] as int,
    configuredRouters: json['configuredRouters'] as int,
    pendingApprovals: json['pendingApprovals'] as int,
    pendingNetworks: json['pendingNetworks'] as int,
    weeklyHeadcount: ((json['weeklyHeadcount'] as List?) ?? [])
        .map((e) => ChartPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    arrivalCurve: ((json['arrivalCurve'] as List?) ?? [])
        .map((e) => ChartPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    presentOnTimeToday: json['presentOnTimeToday'] as int? ?? 0,
    lateToday: json['lateToday'] as int? ?? 0,
    absentToday: json['absentToday'] as int? ?? 0,
    shiftHealth: ((json['shiftHealth'] as List?) ?? [])
        .map((e) => ShiftHealth.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalActiveEmployees: json['totalActiveEmployees'] as int? ?? 0,
    awayCount: json['awayCount'] as int? ?? 0,
    averageArrivalLabel: json['averageArrivalLabel'] as String? ?? '—',
    averageArrivalSublabel: json['averageArrivalSublabel'] as String? ?? '',
    averageArrivalTrendMinutes: json['averageArrivalTrendMinutes'] as int? ?? 0,
    reportsFiledRate: json['reportsFiledRate'] as int? ?? 0,
    reportsFiledFraction: json['reportsFiledFraction'] as String? ?? '0 of 0',
    reportsFiledTrendPct: json['reportsFiledTrendPct'] as int? ?? 0,
    punctualityRatePct: json['punctualityRatePct'] as int? ?? 0,
    punctualityRateTrendPct: json['punctualityRateTrendPct'] as int? ?? 0,
    roster: ((json['roster'] as List?) ?? [])
        .map((e) => RosterEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    dailyBreakdown: ((json['dailyBreakdown'] as List?) ?? [])
        .map((e) => DayRoster.fromJson(e as Map<String, dynamic>))
        .toList(),
    pushNotificationsEnabled: json['pushNotificationsEnabled'] as bool? ?? true,
  );
}

class StatusSplit {
  final int presentPct;
  final int latePct;
  final int absentPct;
  final int present;
  final int late;
  final int absent;

  StatusSplit({
    required this.presentPct,
    required this.latePct,
    required this.absentPct,
    required this.present,
    required this.late,
    required this.absent,
  });

  factory StatusSplit.fromJson(Map<String, dynamic> json) => StatusSplit(
    presentPct: json['presentPct'] as int,
    latePct: json['latePct'] as int,
    absentPct: json['absentPct'] as int,
    present: json['present'] as int,
    late: json['late'] as int,
    absent: json['absent'] as int,
  );
}

class DeptHealthRate {
  final String department;
  final int ratePct;
  final int reportsLast30d;

  DeptHealthRate({
    required this.department,
    required this.ratePct,
    required this.reportsLast30d,
  });

  factory DeptHealthRate.fromJson(Map<String, dynamic> json) => DeptHealthRate(
    department: json['department'] as String,
    ratePct: json['ratePct'] as int,
    reportsLast30d: json['reportsLast30d'] as int,
  );
}

class InsightCard {
  final String title;
  final String body;
  final String tone;

  InsightCard({required this.title, required this.body, required this.tone});

  factory InsightCard.fromJson(Map<String, dynamic> json) => InsightCard(
    title: json['title'] as String,
    body: json['body'] as String,
    tone: json['tone'] as String,
  );
}

class AnalyticsData {
  final StatusSplit status;
  final List<DeptHealthRate> departmentHealth;
  final List<InsightCard> insights;

  AnalyticsData({
    required this.status,
    required this.departmentHealth,
    required this.insights,
  });

  factory AnalyticsData.fromJson(Map<String, dynamic> json) => AnalyticsData(
    status: StatusSplit.fromJson(json['status'] as Map<String, dynamic>),
    departmentHealth: ((json['departmentHealth'] as List?) ?? [])
        .map((e) => DeptHealthRate.fromJson(e as Map<String, dynamic>))
        .toList(),
    insights: ((json['insights'] as List?) ?? [])
        .map((e) => InsightCard.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class TeamMetricsEntry {
  final int userId;
  final int ratePct;
  final int reports;
  final int leads;
  final int punctualityPct;
  final String status;

  TeamMetricsEntry({
    required this.userId,
    required this.ratePct,
    required this.reports,
    required this.leads,
    required this.punctualityPct,
    required this.status,
  });

  factory TeamMetricsEntry.fromJson(Map<String, dynamic> json) =>
      TeamMetricsEntry(
        userId: json['userId'] as int,
        ratePct: json['ratePct'] as int,
        reports: json['reports'] as int,
        leads: json['leads'] as int,
        punctualityPct: json['punctualityPct'] as int,
        status: json['status'] as String,
      );
}

class OfficeCalendarDay {
  final int day;
  final String date;
  final String status;

  OfficeCalendarDay({
    required this.day,
    required this.date,
    required this.status,
  });

  factory OfficeCalendarDay.fromJson(Map<String, dynamic> json) =>
      OfficeCalendarDay(
        day: json['day'] as int,
        date: json['date'] as String,
        status: json['status'] as String,
      );
}

class AttendanceRosterRow {
  final int userId;
  final String name;
  final String department;
  final String? checkInLabel;
  final String? checkOutLabel;
  final String? durationLabel;
  final String status;

  AttendanceRosterRow({
    required this.userId,
    required this.name,
    required this.department,
    required this.checkInLabel,
    required this.checkOutLabel,
    required this.durationLabel,
    required this.status,
  });

  factory AttendanceRosterRow.fromJson(Map<String, dynamic> json) =>
      AttendanceRosterRow(
        userId: json['userId'] as int,
        name: json['name'] as String,
        department: json['department'] as String,
        checkInLabel: json['checkInLabel'] as String?,
        checkOutLabel: json['checkOutLabel'] as String?,
        durationLabel: json['durationLabel'] as String?,
        status: json['status'] as String,
      );
}

class OfficeAttendance {
  final List<OfficeCalendarDay> calendar;
  final String monthLabel;
  final String selectedDate;
  final List<AttendanceRosterRow> dayRoster;
  final int activeEmployeeCount;

  OfficeAttendance({
    required this.calendar,
    required this.monthLabel,
    required this.selectedDate,
    required this.dayRoster,
    required this.activeEmployeeCount,
  });

  factory OfficeAttendance.fromJson(Map<String, dynamic> json) =>
      OfficeAttendance(
        calendar: ((json['calendar'] as List?) ?? [])
            .map((e) => OfficeCalendarDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        monthLabel: json['monthLabel'] as String,
        selectedDate: json['selectedDate'] as String,
        dayRoster: ((json['dayRoster'] as List?) ?? [])
            .map((e) => AttendanceRosterRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeEmployeeCount: json['activeEmployeeCount'] as int,
      );
}

class AdminUser {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final String department;
  final bool isActive;
  final bool isApproved;
  final bool isLocked;
  final DateTime createdAt;
  // Raw "HH:mm:ss" from the backend's TimeOnly — see TimeOfDay parseHHmm below.
  final String shiftStartTime;
  final String shiftEndTime;
  final String shiftType;
  // Today's last successful background ping, if any — the only real signal
  // an admin has that someone's background monitoring has gone quiet (OEM
  // battery killer, geofencing silently died, etc.) instead of just guessing.
  final DateTime? lastSeenAt;

  AdminUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.department,
    required this.isActive,
    required this.isApproved,
    required this.isLocked,
    required this.createdAt,
    this.shiftStartTime = '09:30:00',
    this.shiftEndTime = '17:30:00',
    this.shiftType = 'Day',
    this.lastSeenAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as int,
    username: json['username'] as String,
    fullName: json['fullName'] as String? ?? '',
    role: json['role'] as String,
    department: json['department'] as String? ?? 'Calling',
    isActive: json['isActive'] == true,
    isApproved: json['isApproved'] == true,
    isLocked: json['isLocked'] == true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    shiftStartTime: json['shiftStartTime'] as String? ?? '09:30:00',
    shiftEndTime: json['shiftEndTime'] as String? ?? '17:30:00',
    shiftType: json['shiftType'] as String? ?? 'Day',
    lastSeenAt: json['lastSeenAt'] != null ? DateTime.parse(json['lastSeenAt'] as String) : null,
  );
}

/// Formats a backend "HH:mm:ss" (or "HH:mm") TimeOnly string as "h:mm AM/PM"
/// for display — shared by every shift-related screen/widget.
String formatShiftTime(String hhmmss) {
  final parts = hhmmss.split(':');
  var hour = int.tryParse(parts[0]) ?? 9;
  final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  final period = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12;
  if (hour == 0) hour = 12;
  return '$hour:${minute.toString().padLeft(2, '0')} $period';
}

class AdminAttendance {
  final int id;
  final int userId;
  final String username;
  final String date;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final bool reportSubmitted;

  AdminAttendance({
    required this.id,
    required this.userId,
    required this.username,
    required this.date,
    required this.checkInTime,
    required this.checkOutTime,
    required this.reportSubmitted,
  });

  factory AdminAttendance.fromJson(Map<String, dynamic> json) =>
      AdminAttendance(
        id: json['id'] as int,
        userId: json['userId'] as int? ?? 0,
        username: json['username'] as String,
        date: json['date'] as String,
        checkInTime: DateTime.parse(json['checkInTime'] as String),
        checkOutTime: json['checkOutTime'] != null
            ? DateTime.parse(json['checkOutTime'] as String)
            : null,
        reportSubmitted: json['reportSubmitted'] == true,
      );
}

class AdminReport {
  final int id;
  final String username;
  final String department;
  final String date;
  final int unreadChats;
  final int newLeads;
  final int qualifiedLeads;
  final int followUp;
  final int calls;
  final int potential;
  final int walkIns;
  final int conversion;
  final String? textContent;
  final List<ReportFileRef> files;
  final DateTime submittedAt;
  final DateTime? lastEditedAt;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final String reviewStatus;

  AdminReport({
    required this.id,
    required this.username,
    required this.department,
    required this.date,
    required this.unreadChats,
    required this.newLeads,
    required this.qualifiedLeads,
    required this.followUp,
    required this.calls,
    required this.potential,
    required this.walkIns,
    required this.conversion,
    required this.textContent,
    required this.files,
    required this.submittedAt,
    required this.lastEditedAt,
    required this.checkInTime,
    required this.checkOutTime,
    required this.reviewStatus,
  });

  factory AdminReport.fromJson(Map<String, dynamic> json) => AdminReport(
    id: json['id'] as int,
    username: json['username'] as String,
    department: json['department'] as String? ?? 'Calling',
    date: json['date'] as String,
    unreadChats: json['unreadChats'] as int,
    newLeads: json['newLeads'] as int,
    qualifiedLeads: json['qualifiedLeads'] as int,
    followUp: json['followUp'] as int,
    calls: json['calls'] as int,
    potential: json['potential'] as int,
    walkIns: json['walkIns'] as int,
    conversion: json['conversion'] as int,
    textContent: json['textContent'] as String?,
    files: (json['files'] as List<dynamic>)
        .map((e) => ReportFileRef.fromJson(e as Map<String, dynamic>))
        .toList(),
    submittedAt: DateTime.parse(json['submittedAt'] as String),
    lastEditedAt: json['lastEditedAt'] != null
        ? DateTime.parse(json['lastEditedAt'] as String)
        : null,
    checkInTime: DateTime.parse(json['checkInTime'] as String),
    checkOutTime: json['checkOutTime'] != null
        ? DateTime.parse(json['checkOutTime'] as String)
        : null,
    reviewStatus: json['reviewStatus'] as String? ?? 'New',
  );
}

class AdminRouter {
  final int id;
  final String name;
  final String bssid;
  final bool isActive;
  final DateTime createdAt;

  AdminRouter({
    required this.id,
    required this.name,
    required this.bssid,
    required this.isActive,
    required this.createdAt,
  });

  factory AdminRouter.fromJson(Map<String, dynamic> json) => AdminRouter(
    id: json['id'] as int,
    name: json['name'] as String,
    bssid: json['bssid'] as String,
    isActive: json['isActive'] == true,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class AdminLocation {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool isActive;
  final DateTime createdAt;

  AdminLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.isActive,
    required this.createdAt,
  });

  factory AdminLocation.fromJson(Map<String, dynamic> json) => AdminLocation(
    id: json['id'] as int,
    name: json['name'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    radiusMeters: (json['radiusMeters'] as num).toDouble(),
    isActive: json['isActive'] == true,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class AdminPendingNetwork {
  final int id;
  final String bssid;
  final String? ssid;
  final int attemptCount;
  final DateTime lastSeenAt;

  AdminPendingNetwork({
    required this.id,
    required this.bssid,
    required this.ssid,
    required this.attemptCount,
    required this.lastSeenAt,
  });

  factory AdminPendingNetwork.fromJson(Map<String, dynamic> json) =>
      AdminPendingNetwork(
        id: json['id'] as int,
        bssid: json['bssid'] as String,
        ssid: json['ssid'] as String?,
        attemptCount: json['attemptCount'] as int,
        lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      );
}

class LoginHistoryEntry {
  final int id;
  final String eventType;
  final DateTime timestamp;
  final String? bssid;
  final String? routerName;

  LoginHistoryEntry({
    required this.id,
    required this.eventType,
    required this.timestamp,
    required this.bssid,
    required this.routerName,
  });

  factory LoginHistoryEntry.fromJson(Map<String, dynamic> json) =>
      LoginHistoryEntry(
        id: json['id'] as int,
        eventType: json['eventType'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        bssid: json['bssid'] as String?,
        routerName: json['routerName'] as String?,
      );
}

class AdminUserDetail {
  final AdminUser profile;
  final List<AdminAttendance> attendance;
  final List<LoginHistoryEntry> history;
  final List<AdminReport> reports;

  /// Real accumulated presence today (see AttendanceDurationService) — paired from
  /// every CheckIn/CheckOut cycle so far, so it's already paused for any gap since
  /// the last checkout and picks back up exactly where it left off on the next one.
  /// Admin-only readout — the employee's own app doesn't show this.
  final int todayAccumulatedMinutes;

  /// True while today's most recent cycle is still open (no checkout yet) — the
  /// cue to keep ticking [todayAccumulatedMinutes] forward locally.
  final bool todayStillOpen;

  AdminUserDetail({
    required this.profile,
    required this.attendance,
    required this.history,
    required this.reports,
    this.todayAccumulatedMinutes = 0,
    this.todayStillOpen = false,
  });

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) =>
      AdminUserDetail(
        profile: AdminUser.fromJson(json['profile'] as Map<String, dynamic>),
        attendance: (json['attendance'] as List<dynamic>)
            .map((e) => AdminAttendance.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: (json['history'] as List<dynamic>)
            .map((e) => LoginHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        reports: (json['reports'] as List<dynamic>)
            .map((e) => AdminReport.fromJson(e as Map<String, dynamic>))
            .toList(),
        todayAccumulatedMinutes: json['todayAccumulatedMinutes'] as int? ?? 0,
        todayStillOpen: json['todayStillOpen'] as bool? ?? false,
      );
}

/// One pending "forgot password" request, as an admin sees it — never exposes the
/// requested password itself.
class PendingPasswordResetEntry {
  final int id;
  final int userId;
  final String userName;
  final DateTime requestedAt;

  /// False means this request's device didn't match the account's own home
  /// device — a genuine reinstall/new phone, or someone else entirely. Either
  /// way, verify who's actually asking (call them, ask in person) before approving.
  final bool deviceRecognized;

  PendingPasswordResetEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.requestedAt,
    this.deviceRecognized = true,
  });

  factory PendingPasswordResetEntry.fromJson(Map<String, dynamic> json) => PendingPasswordResetEntry(
        id: json['id'] as int,
        userId: json['userId'] as int,
        userName: json['userName'] as String,
        requestedAt: DateTime.parse(json['requestedAt'] as String),
        deviceRecognized: json['deviceRecognized'] as bool? ?? true,
      );
}

/// One row of the admin Hours list — a person's total real accumulated presence
/// (every check-in/check-out cycle, not just first-in to last-out) over whatever
/// date range is currently selected.
class HoursListEntry {
  final int userId;
  final String name;
  final String department;
  final int totalMinutes;
  final int gapMinutes;

  HoursListEntry({
    required this.userId,
    required this.name,
    required this.department,
    required this.totalMinutes,
    required this.gapMinutes,
  });

  factory HoursListEntry.fromJson(Map<String, dynamic> json) => HoursListEntry(
        userId: json['userId'] as int,
        name: json['name'] as String,
        department: json['department'] as String,
        totalMinutes: json['totalMinutes'] as int,
        gapMinutes: (json['gapMinutes'] as num?)?.toInt() ?? 0,
      );
}

class HoursDay {
  final DateTime date;
  final int minutes;
  final int gapMinutes;
  final bool stillOpen;

  HoursDay({required this.date, required this.minutes, required this.gapMinutes, required this.stillOpen});

  factory HoursDay.fromJson(Map<String, dynamic> json) => HoursDay(
        date: DateTime.parse(json['date'] as String),
        minutes: json['minutes'] as int,
        gapMinutes: (json['gapMinutes'] as num?)?.toInt() ?? 0,
        stillOpen: json['stillOpen'] == true,
      );
}

class HoursDetail {
  final int userId;
  final String name;
  final int totalMinutes;
  final int totalGapMinutes;
  final List<HoursDay> days;

  HoursDetail({
    required this.userId,
    required this.name,
    required this.totalMinutes,
    required this.totalGapMinutes,
    required this.days,
  });

  factory HoursDetail.fromJson(Map<String, dynamic> json) => HoursDetail(
        userId: json['userId'] as int,
        name: json['name'] as String,
        totalMinutes: json['totalMinutes'] as int,
        totalGapMinutes: (json['totalGapMinutes'] as num?)?.toInt() ?? 0,
        days: ((json['days'] as List?) ?? [])
            .map((e) => HoursDay.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
