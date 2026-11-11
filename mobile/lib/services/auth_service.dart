import '../core/api_config.dart';
import '../core/department_utils.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'attendance_away_tracker.dart';
import 'device_id_service.dart';
import 'secure_storage_service.dart';

class LoginResult {
  final AppUser user;
  final bool reportSubmitted;
  final bool attendanceMarked;
  final DateTime checkInTime;
  final DateTime? checkOutTime;

  /// Set only right after a login that just took over this device from a
  /// different account — see AuthController.Login. Null on every checkin()
  /// result, since resuming an existing session never switches accounts.
  final String? deviceSwitchNotice;

  LoginResult({
    required this.user,
    required this.reportSubmitted,
    required this.attendanceMarked,
    required this.checkInTime,
    required this.checkOutTime,
    this.deviceSwitchNotice,
  });
}

class AuthService {
  final ApiClient _api;
  final SecureStorageService _storage;

  AuthService(this._api, this._storage);

  Future<String> register({
    required String username,
    required String password,
    required String fullName,
    required String bssid,
    required String department,
    String? ssid,
    String shiftType = 'Day',
  }) async {
    final result = await _api.post(ApiConfig.register, {
      'username': username,
      'password': password,
      'fullName': fullName,
      'bssid': bssid,
      'ssid': ssid,
      'department': departmentToInt(department),
      'shiftType': shiftTypeToInt(shiftType),
    });
    return result['message'] as String? ?? 'Registration submitted.';
  }

  /// Queues a "forgot password" request for admin approval — never changes the
  /// account's actual password here. Only succeeds when this device is the
  /// account's own HomeDeviceId; the server rejects it otherwise (see
  /// AuthController.ForgotPassword).
  Future<String> forgotPassword({required String username, required String newPassword}) async {
    final deviceId = await getOrCreateDeviceId();
    final result = await _api.post(ApiConfig.forgotPassword, {
      'username': username,
      'deviceId': deviceId,
      'newPassword': newPassword,
    });
    return result['message'] as String? ?? 'Request sent — an admin will review it shortly.';
  }

  Future<LoginResult> remoteAdminLogin(String username, String password) async {
    final result = await _api.post('${ApiConfig.baseUrl}/auth/remote-admin-login', {'username':username, 'password':password});
    await _storage.saveToken(result['token'] as String);
    await _storage.saveLastUsername(username);
    return LoginResult(user: AppUser.fromJson(result['user'] as Map<String, dynamic>),
      reportSubmitted: false, attendanceMarked: false,
      checkInTime: DateTime.parse(result['checkInTime'] as String), checkOutTime: null);
  }

  Future<String> enrollBiometric(String deviceId) async {
    final result = await _api.post(ApiConfig.biometricEnroll, {'deviceId': deviceId});
    return result['credential'] as String;
  }

  Future<LoginResult> biometricLogin({
    required String username,
    required String deviceId,
    required String credential,
    String? bssid,
    String? ssid,
  }) async {
    final result = await _api.post(ApiConfig.biometricLogin, {
      'username': username, 'deviceId': deviceId,
      'credential': credential, 'bssid': bssid, 'ssid': ssid,
    });
    final user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
    if (user.username.trim().toLowerCase() != username.trim().toLowerCase()) {
      throw StateError('Account mismatch: biometric login refused.');
    }
    await _storage.saveToken(result['token'] as String);
    await _storage.saveLastUsername(user.username);
    return LoginResult(
      user: user,
      reportSubmitted: result['reportSubmitted'] == true,
      attendanceMarked: result['attendanceMarked'] == true,
      checkInTime: DateTime.parse(result['checkInTime'] as String),
      checkOutTime: result['checkOutTime'] != null
          ? DateTime.parse(result['checkOutTime'] as String) : null,
    );
  }

  Future<LoginResult> login({
    required String username,
    required String password,
    required String bssid,
    String? ssid,
    double? latitude,
    double? longitude,
    String? deviceId,
    bool developmentBrowserAdmin = false,
  }) async {
    final awaySinceUtc = await AttendanceAwayTracker.pendingDeparture();
    final result = await _api.post(ApiConfig.login, {
      'username': username,
      'password': password,
      'bssid': bssid,
      'ssid': ssid,
      'latitude': latitude,
      'longitude': longitude,
      'deviceId': deviceId,
      'developmentBrowserAdmin': developmentBrowserAdmin,
      if (awaySinceUtc != null) 'awaySinceUtc': awaySinceUtc,
    });

    await AttendanceAwayTracker.clearDeparture();
    await _storage.saveToken(result['token'] as String);
    await _storage.saveLastUsername(username);

    return LoginResult(
      user: AppUser.fromJson(result['user'] as Map<String, dynamic>),
      reportSubmitted: result['reportSubmitted'] == true,
      attendanceMarked: result['attendanceMarked'] == true,
      checkInTime: DateTime.parse(result['checkInTime'] as String),
      checkOutTime: result['checkOutTime'] != null ? DateTime.parse(result['checkOutTime'] as String) : null,
      deviceSwitchNotice: result['deviceSwitchNotice'] as String?,
    );
  }

  /// Called on every app open once a token is already stored — this is what lets the
  /// user avoid re-entering credentials: just being on the approved network is enough
  /// to silently re-authenticate and mark today's attendance if not already marked.
  Future<LoginResult> checkin(String bssid, {String? ssid, bool developmentBrowserAdmin = false}) async {
    final deviceId = await getOrCreateDeviceId();
    final awaySinceUtc = await AttendanceAwayTracker.pendingDeparture();
    final result = await _api.post(ApiConfig.checkin, {
      'deviceId': deviceId,
      'bssid': bssid,
      'ssid': ssid,
      'developmentBrowserAdmin': developmentBrowserAdmin,
      if (awaySinceUtc != null) 'awaySinceUtc': awaySinceUtc,
    });

    await AttendanceAwayTracker.clearDeparture();
    await _storage.saveToken(result['token'] as String);

    return LoginResult(
      user: AppUser.fromJson(result['user'] as Map<String, dynamic>),
      reportSubmitted: result['reportSubmitted'] == true,
      attendanceMarked: result['attendanceMarked'] == true,
      checkInTime: DateTime.parse(result['checkInTime'] as String),
      checkOutTime: result['checkOutTime'] != null ? DateTime.parse(result['checkOutTime'] as String) : null,
    );
  }

  Future<AppUser> changeCredentials({required String currentPassword, String? newUsername, String? newPassword}) async {
    final result = await _api.post(ApiConfig.changeCredentials, {
      'currentPassword': currentPassword,
      if (newUsername != null && newUsername.isNotEmpty) 'newUsername': newUsername,
      if (newPassword != null && newPassword.isNotEmpty) 'newPassword': newPassword,
    });

    final user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
    await _storage.saveLastUsername(user.username);
    return user;
  }

  /// Re-authentication checkpoint (e.g. before an Admin can set a new password
  /// for someone else) — true if [password] matches the CURRENTLY signed-in
  /// user's own password.
  Future<bool> verifyOwnPassword(String password) async {
    try {
      await _api.post(ApiConfig.verifyPassword, {'password': password});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns null on success, or an error message on failure.
  Future<String?> logout() async {
    try {
      await _api.post(ApiConfig.logout, {});
    } catch (_) {
      // Offline sign-out must still invalidate this device's saved session.
      // The backend's stale-attendance monitor will close a missed checkout.
    } finally {
      await _storage.clearToken();
      await AttendanceAwayTracker.clearDeparture();
    }
    return null;
  }

  /// Records a checkout without ending the session — used when the connectivity
  /// monitor detects the device left the approved network. Best-effort: the backend
  /// is cloud-hosted and usually still reachable, but failures are swallowed rather
  /// than surfaced to the user in case there's no connectivity at all at that moment.
  Future<void> markCheckoutSilently() async {
    await AttendanceAwayTracker.noteDeparture();
    try {
      await _api.post(ApiConfig.logout, {});
      await AttendanceAwayTracker.clearDeparture();
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }
  }

  Future<void> forceClearSession() => _storage.clearToken();

  Future<bool> hasStoredToken() async => (await _storage.readToken()) != null;
}
