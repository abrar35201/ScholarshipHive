import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Account-scoped biometric enrollment. Credential is a server-protected
/// device-bound ticket, NOT a password or someone else's live auth session.
class BiometricLockService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _key(String username) =>
      'biometric_account_v2_${Uri.encodeComponent(username.trim().toLowerCase())}';

  static Future<bool> isDeviceSupported() async {
    if (kIsWeb) return false;
    try {
      return (await _auth.canCheckBiometrics) &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabledFor(String username) async =>
      username.trim().isNotEmpty && await _storage.containsKey(key: _key(username));

  static Future<String?> credentialFor(String username) =>
      _storage.read(key: _key(username));

  static Future<void> enroll(String username, String credential) =>
      _storage.write(key: _key(username), value: credential);

  static Future<void> disable(String username) =>
      _storage.delete(key: _key(username));

  static Future<bool> authenticate() async {
    if (!await isDeviceSupported()) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Verify fingerprint for ScholarshipHive',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
