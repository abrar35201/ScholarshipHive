import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'attendance_away_tracker.dart';
import 'network_service.dart';
import 'notification_service.dart';
import 'office_geofence_service.dart';
import 'remote_config_service.dart';
import 'secure_storage_service.dart';

final NotificationService _notifications = NotificationService();

/// Google Play policy (effective Aug 26, 2026) disallows an app-owned
/// foreground service that just runs all day "in case" a geofence changes —
/// it must be tied to a discrete event and stop right after. This file is
/// the one place that discrete "did I actually check in/out" work happens,
/// invoked from three independent triggers that never keep a service running
/// between calls:
///   1. A real geofence ENTER/EXIT transition (office_geofence_service.dart),
///      which briefly promotes itself to a foreground service for the few
///      seconds this needs (Android hides the real Wi-Fi BSSID from a
///      background-priority process, so reading it still needs *some*
///      foreground promotion — just not an all-day one).
///   2. A periodic WorkManager task (every 15 minutes, Android's own floor)
///      while a zone is marked "inside" — a safety net for the case where
///      Wi-Fi dropped without a GPS exit (see office_geofence_service.dart).
///   3. An FCM watchdog wake, only when it looks like #2 has gone quiet.
const String periodicTaskUniqueName = 'attendance_periodic_check';
const String periodicTaskName = 'attendanceperiodiccheck';
const String oneOffTaskUniqueName = 'attendance_oneoff_check';
const String oneOffTaskName = 'attendanceoneoffcheck';
const String _lastNotifiedDateKey = 'last_notified_welcome_date';
const String _wasOnApprovedNetworkKey = 'bg_was_on_approved_network';
const String lastAttendanceCheckAtKey = 'last_attendance_check_at_millis';
const String _wifiDisconnectedSinceKey = 'wifi_disconnected_since_millis';

/// How long a Wi-Fi drop is tolerated, while GPS still confirms the device is
/// inside an approved office radius, before it's treated as a real departure.
/// Routers reboot, APs hiccup, someone's phone drops to a weak corner of the
/// building for a minute — none of that is "left for the day," so a bare Wi-Fi
/// failure alone shouldn't immediately record a checkout the way it used to.
const Duration wifiDisconnectGracePeriod = Duration.zero;

/// The actual check: read Wi-Fi, decide check-in/out/nothing, notify once a
/// day. Safe to call from any isolate (WorkManager's own, or a geofence
/// callback's) — every dependency is constructed fresh, nothing shared.
/// Returns quickly either way; callers are responsible for wrapping this in
/// whatever brief foreground-service promotion their trigger needs.
Future<void> runAttendanceCheck() async {
  try {
    // Isolate-local: a background WorkManager/geofence invocation is a fresh
    // isolate each time, with none of the main app's already-resolved state —
    // see RemoteConfigService for why this has to run here too, not just once
    // in main(), for the backend URL to ever actually self-heal in the
    // background instead of only when someone happens to reopen the app.
    await RemoteConfigService.init();

    final storage = SecureStorageService();
    final token = await storage.readToken();
    if (token == null) return; // Nobody logged in on this device.

    // Outside every approved GPS radius means there's nothing here worth
    // doing at all — no Wi-Fi scan, no server call, no heartbeat update. A
    // router's Wi-Fi range reaches well past the building itself, so without
    // this, a device sitting right at the edge of that range (but genuinely
    // outside the actual radius) could keep getting silently checked in
    // every time it caught a stray bar of signal — the exact "kept running
    // for a full hour after leaving" symptom this closes. The moment a real
    // geofence ENTER (or the next successful GPS fix) flips this back to
    // "inside", checks resume immediately — this isn't a standing sleep, just
    // a per-tick skip while there's truly nothing to check.
    if (!await isCurrentlyInsideAnyZone()) return;

    final api = ApiClient(storage);
    final networkService = NetworkService(api);
    final authService = AuthService(api, storage);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(lastAttendanceCheckAtKey, DateTime.now().millisecondsSinceEpoch);
    // Every real call here (periodic loop, FCM watchdog nudge, geofence ENTER)
    // only ever fires while a zone is considered "inside" — refreshing the
    // heartbeat notification's timestamp on every tick, not just on state
    // changes, is what makes it a live "still alive" signal rather than a
    // one-off that goes stale the moment nothing changes for hours.
    try {
      await _notifications.showMonitoringHeartbeat();
    } catch (_) {}

    final outcome = await networkService.checkNetwork();
    final wasOnApprovedNetwork = prefs.getBool(_wasOnApprovedNetworkKey) ?? false;

    // Neither a transient server hiccup nor Android's own background BSSID
    // masking (still possible for the first second or two right after
    // promoting to foreground) means "the user left" — both look identical
    // to !allowed but neither one means they actually left the building.
    if (outcome.unreachable || outcome.ambiguous) return;

    if (!outcome.allowed || outcome.bssid == null) {
      if (!wasOnApprovedNetwork) return; // Already off-network — nothing pending to resolve.
      await AttendanceAwayTracker.noteDeparture();

      final stillInsideRadius = await isCurrentlyInsideAnyZone();
      if (!stillInsideRadius) {
        // GPS itself says the device has left — not a Wi-Fi hiccup, a real
        // departure. (The geofence EXIT callback usually beats this to the
        // punch already; this is just the backup path catching up.)
        await authService.markCheckoutSilently();
        await prefs.setBool(_wasOnApprovedNetworkKey, false);
        await prefs.remove(_wifiDisconnectedSinceKey);
        return;
      }

      final now = DateTime.now();
      final disconnectedSinceMillis = prefs.getInt(_wifiDisconnectedSinceKey);
      if (disconnectedSinceMillis == null) {
        // First check to notice the drop while still inside the radius —
        // start the grace timer rather than checking out immediately.
        await prefs.setInt(_wifiDisconnectedSinceKey, now.millisecondsSinceEpoch);
        // No grace window: Wi-Fi departure is not credited as working time.
        await authService.markCheckoutSilently();
        await prefs.setBool(_wasOnApprovedNetworkKey, false);
        return;
      }

      final disconnectedFor = now.difference(DateTime.fromMillisecondsSinceEpoch(disconnectedSinceMillis));
      if (disconnectedFor < wifiDisconnectGracePeriod) {
        return; // Still within the grace window — keep the session running.
      }

      // Router's been unreachable for too long even though GPS still says
      // we're on-site (genuinely down, not a blip) — treat it as a real
      // checkout now. Also force the GPS-side cache to "outside": it's the
      // one that's been stuck (a real EXIT transition should have caught
      // this already but evidently hasn't), and leaving it stale is what
      // would keep the backup loop running this same Wi-Fi check every few
      // minutes indefinitely — this is the actual departure signal winning
      // out over a GPS side that hasn't caught up yet.
      await authService.markCheckoutSilently();
      await markAllZonesExited();
      await prefs.setBool(_wasOnApprovedNetworkKey, false);
      await prefs.remove(_wifiDisconnectedSinceKey);
      return;
    }

    // Back on an approved network — clear any pending grace timer. If this
    // resolves within the grace window above, no checkout was ever recorded,
    // so this continues the SAME session rather than starting a new one.
    await prefs.remove(_wifiDisconnectedSinceKey);
    await prefs.setBool(_wasOnApprovedNetworkKey, true);

    final todayKey = _todayKey();
    if (prefs.getString(_lastNotifiedDateKey) != todayKey) {
      await NotificationService().showWelcome();
      await prefs.setString(_lastNotifiedDateKey, todayKey);
    }

    await authService.checkin(outcome.bssid!, ssid: outcome.ssid);
  } catch (_) {
    // A single failed check shouldn't propagate — there's always another
    // trigger along shortly (periodic task, next geofence event, or FCM).
  }
}

String _todayKey() {
  // Matches the server's attendance business-day boundary (7 AM, not
  // midnight — see DateTimeExtensions.PakistanToday on the backend).
  final shifted = DateTime.now().subtract(const Duration(hours: 7));
  return '${shifted.year}-${shifted.month}-${shifted.day}';
}

/// WorkManager's own background isolate entry point — registered once in
/// main() via `Workmanager().initialize(workmanagerCallbackDispatcher)`.
/// Handles both the periodic backup check and the watchdog-triggered one-off
/// check identically; which one ran is only relevant for logging.
@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await runAttendanceCheck();
    return true;
  });
}

/// Starts the 15-minute backup verification loop — call once a zone is
/// confirmed "inside"; a no-op if already scheduled. This is deliberately
/// NOT the primary way arrivals/departures are detected (the geofence
/// transition itself is), just a safety net for staying accurate while
/// someone sits inside a zone for hours.
Future<void> scheduleAttendancePeriodicCheck() async {
  await Workmanager().registerPeriodicTask(
    periodicTaskUniqueName,
    periodicTaskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    foregroundServiceConfig: ForegroundServiceConfig(
      notificationTitle: 'ScholarshipHive',
      notificationText: 'Confirming you\'re still on an approved network.',
      notificationChannelId: 'scholarshiphive_attendance',
      notificationChannelName: 'Attendance monitoring',
      // Not "location" — this task's own foreground promotion isn't the
      // location-tracking mechanism itself (the geofence API already does
      // that without needing a service); it's just what's needed to read
      // the real Wi-Fi BSSID for the few seconds this task runs.
      foregroundServiceType: ForegroundServiceType.shortService,
    ),
  );
}

/// Stops the backup loop — call once no zones are left "inside".
Future<void> cancelAttendancePeriodicCheck() async {
  await Workmanager().cancelByUniqueName(periodicTaskUniqueName);
}

/// Enqueues a single immediate check, promoted to a brief foreground service
/// the same way the periodic task is. Used by the FCM watchdog (fcm_service.dart)
/// when the periodic loop looks like it's gone quiet on some OEM, and it's not
/// safe to just do the check inline in the FCM handler's own tight execution
/// budget (a Wi-Fi scan can be slow, and the handler isn't itself running as a
/// foreground service, so a fresh BSSID read there could come back masked).
Future<void> enqueueAttendanceOneOffCheck() async {
  await Workmanager().registerOneOffTask(
    oneOffTaskUniqueName,
    oneOffTaskName,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    foregroundServiceConfig: ForegroundServiceConfig(
      notificationTitle: 'ScholarshipHive',
      notificationText: 'Confirming you\'re still on an approved network.',
      notificationChannelId: 'scholarshiphive_attendance',
      notificationChannelName: 'Attendance monitoring',
      foregroundServiceType: ForegroundServiceType.shortService,
    ),
  );
}
