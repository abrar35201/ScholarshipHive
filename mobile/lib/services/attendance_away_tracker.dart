import 'package:shared_preferences/shared_preferences.dart';

/// Device-observed departure, kept until the server confirms a new check-in.
/// This is not an authentication mechanism; the backend enforces office BSSID,
/// geofence (when required), token and original-device binding independently.
class AttendanceAwayTracker {
  static const _key = 'attendance_away_since_utc';

  static Future<void> noteDeparture() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_key)) {
      await prefs.setString(_key, DateTime.now().toUtc().toIso8601String());
    }
  }

  static Future<String?> pendingDeparture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clearDeparture() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
