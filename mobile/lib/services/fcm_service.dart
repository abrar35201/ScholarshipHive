import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_config.dart';
import 'api_client.dart';
import 'attendance_check_worker.dart';
import 'office_geofence_service.dart';
import 'secure_storage_service.dart';

/// A wake ping arrives roughly every 10 minutes (see FcmWakeService on the
/// backend); anything under ~12 minutes since the last successful check just
/// means the 15-minute periodic loop is on schedule — no need to nudge it
/// early every single wake.
const Duration _watchdogStaleThreshold = Duration(minutes: 12);

/// A lightweight watchdog, NOT the thing that actually does the Wi-Fi check
/// itself — this handler's own execution window is too tight (and it isn't
/// running as a foreground service, so a fresh BSSID read here could come
/// back masked) to safely run the real check inline. Its only two jobs:
/// (1) re-register geofences if an OEM battery manager wiped them since the
/// last wake, and (2) if it looks like the 15-minute backup loop has gone
/// quiet while a zone is still marked "inside" (that OEM killed WorkManager
/// too), nudge a one-off check via attendance_check_worker.dart — which does
/// its own brief foreground-service promotion to read Wi-Fi correctly. Must
/// be a top-level function (not a class method) and carry this annotation:
/// the plugin spawns a fresh background isolate to run it when the app is
/// killed, and this is how Flutter finds the entry point there.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    final storage = SecureStorageService();
    final token = await storage.readToken();
    if (token == null) return; // Nobody's logged in on this device.

    // Self-healing: this wake-up is also our chance to bring geofence
    // registration back if an OEM battery manager (or a device reboot) wiped
    // it since the last wake — a no-op if already registered. Its own fresh
    // GPS read decides whether the 15-minute backup loop should be running
    // right now, NOT this handler directly.
    bool insideGeofence;
    try {
      insideGeofence = await OfficeGeofenceService.start();
    } catch (_) {
      insideGeofence = false;
    }
    // Nothing to watch for from outside the office radius — check-in would
    // fail the mandatory location gate regardless of what router this is.
    if (!insideGeofence) return;

    final prefs = await SharedPreferences.getInstance();
    final lastCheckMillis = prefs.getInt(lastAttendanceCheckAtKey) ?? 0;
    final sinceLastCheck = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastCheckMillis));
    if (sinceLastCheck < _watchdogStaleThreshold) {
      return; // The periodic loop is still on schedule.
    }

    await enqueueAttendanceOneOffCheck();
  } catch (_) {
    // A wake ping failing shouldn't crash this isolate — there'll be another
    // one along shortly, plus the 15-minute periodic loop as backup.
  }
}

class FcmService {
  static Future<void> init() async {
    if (kIsWeb) return;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    // The app being in the foreground already means the regular foreground
    // service is ticking on its own, but handling this too is free and closes
    // any gap right around a cold start before that service has spun up.
    FirebaseMessaging.onMessage.listen(fcmBackgroundHandler);
    listenForTokenRefresh();
  }

  /// Call after login/app-open so the server always has this device's
  /// current token — tokens can rotate at any time, so this isn't a one-time
  /// registration.
  static Future<void> registerToken() async {
    if (kIsWeb) return;
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) return;
      final storage = SecureStorageService();
      final api = ApiClient(storage);
      await api.post(ApiConfig.registerFcmToken, {'token': fcmToken});
    } catch (_) {
      // Best-effort — the app still works via the foreground service and
      // geofence without this, just with one less wake path.
    }
  }

  static void listenForTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => registerToken());
  }
}
