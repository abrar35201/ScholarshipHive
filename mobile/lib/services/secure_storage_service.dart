import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _tokenKey = 'auth_token';
  static const _usernameKey = 'last_username';
  static const _biometricLockKey = 'biometric_lock_active';
  static const _remoteAdminKey = 'remote_admin_session';

  final _storage = const FlutterSecureStorage();
  String? _cachedToken;
  bool _tokenLoaded = false;

  /// Every read on this class sits on the app's cold-start critical path
  /// (SplashScreen never gets past "Checking your network…" until these
  /// resolve) — but flutter_secure_storage is backed by the Android Keystore,
  /// which on a real (rare, but observed) slice of devices can simply hang
  /// forever on first access after a fresh install, with no error and no
  /// native-side timeout of its own. Bounding every read here the same way
  /// the geofence check is already bounded (see OfficeGeofenceService.start)
  /// means a stuck Keystore strands someone on the splash screen for a few
  /// seconds instead of indefinitely — falling back to "nothing stored yet"
  /// is exactly as safe as a genuinely fresh install with no token.
  Future<String?> _readWithTimeout(String key) =>
      _storage.read(key: key).timeout(const Duration(seconds: 5), onTimeout: () => null);

  Future<void> saveRemoteAdminSession(bool active) =>
      active ? _storage.write(key: _remoteAdminKey, value: '1') : _storage.delete(key: _remoteAdminKey);
  Future<bool> readRemoteAdminSession() async => (await _readWithTimeout(_remoteAdminKey)) != null;

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _cachedToken = token;
    _tokenLoaded = true;
  }
  Future<String?> readToken() async {
    if (_tokenLoaded) return _cachedToken;
    final token = await _readWithTimeout(_tokenKey);
    if (token != null) {
      _cachedToken = token;
      _tokenLoaded = true;
    }
    return token;
  }
  Future<void> clearToken() async {
    _cachedToken = null;
    _tokenLoaded = true;
    await _storage.delete(key: _tokenKey);
  }

  Future<void> saveLastUsername(String username) =>
      _storage.write(key: _usernameKey, value: username);
  Future<String?> readLastUsername() => _readWithTimeout(_usernameKey);
  Future<void> clearLastUsername() => _storage.delete(key: _usernameKey);

  /// Whether "Log Out" (with fingerprint lock enabled) left the app re-locked —
  /// has to survive an actual app-process restart, not just live in memory,
  /// since Android freely kills a backgrounded app between "Log Out" and the
  /// person reopening it. A plain in-memory counter reset to 0 on every fresh
  /// process, silently dropping the lock and going straight back into the app.
  Future<void> saveBiometricLockActive(bool active) =>
      active ? _storage.write(key: _biometricLockKey, value: '1') : _storage.delete(key: _biometricLockKey);
  Future<bool> readBiometricLockActive() async => (await _readWithTimeout(_biometricLockKey)) != null;
}
