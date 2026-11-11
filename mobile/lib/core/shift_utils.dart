import 'package:flutter/material.dart';

/// Parses "HH:mm:ss" (see AppUser.shiftStartTime/shiftEndTime, AdminUser's
/// equivalents) into a TimeOfDay — shared by [shiftDuration] and by whatever
/// anchors a shift-start instant, so every reader agrees on exactly the same
/// interpretation of a possibly-malformed value.
TimeOfDay parseShiftTimeOfDay(String? raw, {TimeOfDay fallback = const TimeOfDay(hour: 9, minute: 30)}) {
  final parts = raw?.split(':');
  if (parts == null || parts.length < 2) return fallback;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return fallback;
  return TimeOfDay(hour: hour, minute: minute);
}

/// How long the shift actually runs — wrapping past midnight for a night
/// shift whose end time is numerically earlier than its start time, rather
/// than coming out negative.
Duration shiftDuration(String? startTime, String? endTime) {
  final start = parseShiftTimeOfDay(startTime);
  final end = parseShiftTimeOfDay(endTime, fallback: const TimeOfDay(hour: 17, minute: 30));
  final startMinutes = start.hour * 60 + start.minute;
  var endMinutes = end.hour * 60 + end.minute;
  if (endMinutes <= startMinutes) endMinutes += 24 * 60;
  return Duration(minutes: endMinutes - startMinutes);
}
