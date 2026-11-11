import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

const String _deviceIdKey = 'device_install_id';

/// A random ID generated once per app install and never rotated — stands in for
/// "this physical device" for AuthController.Login's device-switch handling.
/// Not a hardware identifier: Android no longer exposes one to normal apps
/// without extra permissions, and device_info_plus's own `id` field is a build
/// fingerprint that's often identical across every device running the same
/// firmware image, not a per-device value. A random per-install ID is enough
/// to notice "this phone was just someone else's account a moment ago" within
/// a single install, which is the actual case this protects against — logging
/// in as a different person on a shared/borrowed phone without ever properly
/// logging out first (see office_geofence_service.dart's notes on why that
/// silently hands the phone's background attendance tracking to whoever
/// logged in most recently).
Future<String> getOrCreateDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_deviceIdKey);
  if (existing != null && existing.isNotEmpty) return existing;

  final random = Random.secure();
  final id = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  await prefs.setString(_deviceIdKey, id);
  return id;
}
