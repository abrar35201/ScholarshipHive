import 'package:flutter/foundation.dart';

/// Central place to point the app at your backend.
///
/// The backend is hosted on Railway — this is its default public URL, baked
/// in at build time. [serverUrl] is NOT a compile-time constant, though: it
/// starts as this default and can be overwritten at runtime by
/// RemoteConfigService (see that file for the full story) if Firebase Remote
/// Config has a different value on record. That's what lets an already-
/// installed app find its way to a NEW backend on its own — without that,
/// the day the backend's URL changes (a Railway account migration, a plan
/// expiring, anything), every phone that hadn't already picked up a new APK
/// build would be stuck forever: the self-update check itself lives on the
/// same server that just moved, so there'd be no way for it to ever
/// discover where to look next.
///
/// Still overridable at build time too, same as before:
///   flutter build apk --release --dart-define=API_SERVER_URL=https://new-domain
/// Omitting the flag keeps today's default, so existing build commands and
/// CI scripts don't need to change at all. This only matters for brand new
/// installs, or as the starting point Remote Config then confirms/overrides.
class ApiConfig {
  static const String _compiledInDefault = String.fromEnvironment(
    'API_SERVER_URL',
    defaultValue: kIsWeb && kDebugMode
        ? 'http://localhost:5080'
        : 'https://scholarshiphive-backend-production-526c0ddb.up.railway.app',
  );

  /// Local Chrome development uses a dev-only admin login path because browser
  /// APIs cannot read a Wi-Fi BSSID or register native geofences.
  static const bool useDevelopmentBrowserAdminAuth = kIsWeb && kDebugMode;
  static const String developmentBrowserAdminBssid = '00:00:00:00:00:00';

  // An explicitly selected development backend must not be silently replaced
  // by a Firebase Remote Config value (e.g. a production Railway URL).
  static const String _explicitServerUrl = String.fromEnvironment('API_SERVER_URL', defaultValue: '');
  static String _serverUrl = _compiledInDefault;
  static String get serverUrl => _serverUrl;

  /// Called once by RemoteConfigService.init() after a (successful or
  /// cached) Remote Config fetch. Ignores a blank/missing value rather than
  /// ever pointing the app at nothing.
  static void applyRemoteServerUrl(String? url) {
    if (_explicitServerUrl.isNotEmpty) return;
    final trimmed = url?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _serverUrl = trimmed;
    }
  }

  static String get baseUrl => '$serverUrl/api';
  static String get hubUrl => '$serverUrl/hubs/attendance';

  static String get checkNetwork => '$baseUrl/auth/check-network';
  static String get register => '$baseUrl/auth/register';
  static String get forgotPassword => '$baseUrl/auth/forgot-password';
  static String get login => '$baseUrl/auth/login';
  static String get biometricEnroll => '$baseUrl/auth/biometric-enroll';
  static String get biometricLogin => '$baseUrl/auth/biometric-login';
  static String get checkin => '$baseUrl/auth/checkin';
  static String get changeCredentials => '$baseUrl/auth/change-credentials';
  static String get verifyPassword => '$baseUrl/auth/verify-password';
  static String get logout => '$baseUrl/auth/logout';
  static String get geofenceLocations => '$baseUrl/auth/geofence-locations';
  static String get registerFcmToken => '$baseUrl/auth/register-fcm-token';
  static String get geofenceStatus => '$baseUrl/auth/geofence-status';
  static String get submitReport => '$baseUrl/reports';
  static String get myReports => '$baseUrl/reports/mine';
  static String reportFile(int id) => '$baseUrl/reports/files/$id';
  static String get myAttendance => '$baseUrl/attendance/mine';

  static String get adminDashboard => '$baseUrl/admin/dashboard';
  static String get adminAnalytics => '$baseUrl/admin/analytics';
  static String get adminTeamMetrics => '$baseUrl/admin/team-metrics';
  static String get adminOfficeAttendance => '$baseUrl/admin/attendance/office';
  static String get adminUsers => '$baseUrl/admin/users';
  static String get adminAttendance => '$baseUrl/admin/attendance';
  static String get adminReports => '$baseUrl/admin/reports';
  static String get adminRouters => '$baseUrl/admin/routers';
  static String get adminLocations => '$baseUrl/admin/locations';
  static String get adminPendingNetworks => '$baseUrl/admin/pending-networks';
  static String get adminHours => '$baseUrl/admin/hours';
  static String adminHoursDetail(int userId) => '$baseUrl/admin/hours/$userId';
  static String get adminPasswordResets => '$baseUrl/admin/password-resets';
  static String adminReportFile(int id) => '$baseUrl/admin/reports/files/$id';
  static String adminReportSignOff(int id) => '$baseUrl/admin/reports/$id/sign-off';
  static String adminReportFlag(int id) => '$baseUrl/admin/reports/$id/flag';
  static String adminReportAskForDetail(int id) => '$baseUrl/admin/reports/$id/ask-for-detail';
  static String get adminChat => '$baseUrl/admin/chat';
  static String get adminChatStatus => '$baseUrl/admin/chat/status';

  static String get auditReports => '$baseUrl/audit-reports';
  static String auditReportFile(int id) => '$baseUrl/audit-reports/files/$id';

  static const Duration timeout = Duration(seconds: 10);
}
