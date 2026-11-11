import '../models/admin_models.dart';

/// One check-in → check-out pairing, built from a user's raw login/logout
/// event log.
class CheckCycle {
  final LoginHistoryEntry? checkIn;
  final LoginHistoryEntry? checkOut;
  const CheckCycle({this.checkIn, this.checkOut});
}

/// Pairs a flat, newest-first login/logout event log into Check-In→Check-Out
/// cycles, grouped by the calendar day (local time) each cycle falls on —
/// shared by the full per-user History tab and the Attendance tab's
/// single-day drill-down so both agree on exactly the same pairing.
Map<DateTime, List<CheckCycle>> groupHistoryByDay(List<LoginHistoryEntry> items) {
  // Walk oldest-first to pair events correctly, then re-reverse each day's
  // cycles so the newest cycle still shows first within its day.
  final chronological = items.reversed.toList();
  final byDay = <DateTime, List<CheckCycle>>{};
  LoginHistoryEntry? pendingCheckIn;

  for (final e in chronological) {
    final local = e.timestamp.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final cycles = byDay.putIfAbsent(day, () => []);

    if (e.eventType == 'CheckIn') {
      if (pendingCheckIn != null) cycles.add(CheckCycle(checkIn: pendingCheckIn));
      pendingCheckIn = e;
    } else {
      cycles.add(CheckCycle(checkIn: pendingCheckIn, checkOut: e));
      pendingCheckIn = null;
    }
  }
  if (pendingCheckIn != null) {
    final local = pendingCheckIn.timestamp.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(day, () => []).add(CheckCycle(checkIn: pendingCheckIn));
  }

  for (final cycles in byDay.values) {
    cycles.sort((a, b) {
      final aTime = (a.checkOut ?? a.checkIn)!.timestamp;
      final bTime = (b.checkOut ?? b.checkIn)!.timestamp;
      return bTime.compareTo(aTime);
    });
  }
  return byDay;
}
