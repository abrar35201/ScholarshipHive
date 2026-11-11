import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_config.dart';
import 'api_client.dart';
import 'attendance_check_worker.dart';
import 'auth_service.dart';
import 'attendance_away_tracker.dart';
import 'notification_service.dart';
import 'remote_config_service.dart';
import 'secure_storage_service.dart';

const String _zonesInsideKey = 'geofence_zones_currently_inside';

/// Tracks which of the (possibly several) approved office zones this device is
/// currently inside, so exiting ONE office location doesn't get reported to
/// the server as "left the building" while still standing inside another one.
/// Only reports "outside" once the set is empty; reports "inside" on any entry.
Future<void> _updateZoneMembership(String zoneId, bool entered) async {
  final prefs = await SharedPreferences.getInstance();
  final zones = (prefs.getStringList(_zonesInsideKey) ?? []).toSet();
  if (entered) {
    zones.add(zoneId);
  } else {
    zones.remove(zoneId);
  }
  await _reportInsideStatus(zones);
}

/// Whether the last geofence transition (or the fresh-position check right
/// after registering zones) says this device is inside at least one approved
/// office zone — a cheap SharedPreferences read, not a fresh GPS request.
/// Used by the Wi-Fi disconnect grace period in attendance_check_worker.dart
/// to tell "still physically in the building, router just blipped" apart from
/// "actually left" without paying for a location fix on every check.
Future<bool> isCurrentlyInsideAnyZone() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(_zonesInsideKey) ?? []).isNotEmpty;
}

/// Force-clears zone membership and stops the backup loop — called by
/// attendance_check_worker.dart when the Wi-Fi signal itself (not GPS) is the
/// one deciding "this device has actually left": a real GPS geofence EXIT
/// can be delayed or missed entirely (Android's own geofencing isn't 100%
/// reliable, especially indoors or under aggressive OEM battery management),
/// and standing right at the edge of the office Wi-Fi's range — which
/// reaches further than the GPS radius — can make it flicker back "allowed"
/// every few minutes without ever crossing back into the actual radius. Left
/// alone, that combination meant the GPS-side cache could stay stuck
/// "inside" indefinitely: every periodic/FCM tick would trust that stale
/// cache and keep the backup loop (and its Wi-Fi checks) running long after
/// the person genuinely left, exactly the "kept running for a full hour
/// outside" symptom this closes.
Future<void> markAllZonesExited() async {
  await _reportInsideStatus(<String>{});
}

Future<void> _reportInsideStatus(Set<String> insideZoneIds) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_zonesInsideKey, insideZoneIds.toList());

  final inside = insideZoneIds.isNotEmpty;

  final storage = SecureStorageService();
  final token = await storage.readToken();
  if (token == null) return;
  try {
    final api = ApiClient(storage);
    await api.post(ApiConfig.geofenceStatus, {'inside': inside});
  } catch (_) {
    // Best-effort — Login/Checkin fall back to "unknown" (not blocking) if
    // the server never heard from us, so a failed report here just means one
    // less confirmation, not a stuck lockout.
  }

  // The 15-minute backup verification loop is only useful while actually at
  // an approved office location — outside the radius there's nothing to
  // re-verify. This is the single place that decides whether it should be
  // scheduled right now, so every path that reports a status (a real
  // transition, or the fresh-position check below) keeps it in sync.
  //
  // The heartbeat notification lives alongside it for the same reason: the
  // new discrete-event design (see officeGeofenceCallback's doc comment)
  // deliberately leaves nothing visible between checks, which makes a real
  // failure indistinguishable from normal silence. Updating it here means
  // every path that can flip "inside" status — a real transition or this
  // fallback resync — also refreshes the one thing a user can actually look
  // at to tell the background monitoring is alive.
  try {
    if (inside) {
      await scheduleAttendancePeriodicCheck();
      await NotificationService().showMonitoringHeartbeat();
    } else {
      await cancelAttendancePeriodicCheck();
      // Every notification this app has shown, not just the heartbeat —
      // leaving the office means nothing here is still worth watching, so
      // nothing should still be sitting in the tray either (including a
      // same-day "Welcome" notification from earlier, which otherwise just
      // lingered until the user dismissed it themselves).
      await NotificationService().clearAll();
    }
  } catch (_) {}
}

/// A geofence transition alone can miss the case where the device is ALREADY
/// sitting inside a zone the moment monitoring (re)starts — a fresh install,
/// a reboot, or the geofence registration being resurrected after dying all
/// skip straight past the "crossing the boundary" moment a transition is
/// built to catch. Doing one direct GPS read right after (re)registering
/// zones closes that gap.
///
/// GPS itself is unreliable INDOORS — exactly where every real user of this
/// is standing when this runs — so a request that comes back with no fix at
/// all (no fresh read, no last-known either) is common and must NOT be read
/// as "not inside": this used to return false in that case, which fed
/// straight into OfficeGeofenceService.start()'s return value and blocked
/// the whole app on a "Location isn't confirmed yet" screen (see
/// AppProvider.refreshNetworkAndSession) every single time the app opened
/// with a weak indoor GPS signal, even for someone who had a confirmed
/// geofence ENTER on record minutes earlier and never actually left.
///
/// When GPS genuinely has nothing to offer, this re-asserts the last known
/// geofence status to the SERVER too (not just the local app-side gate) —
/// the backend has its own independent copy of "is this device inside"
/// (User.IsInsideGeofence, checked by Login/Checkin — see
/// AuthController.GeofenceStatus) that ONLY changes on a real transition or a
/// successful fresh GPS report. Without re-sending the cached status here,
/// a single earlier exit (a real departure, or GPS jitter right at the
/// boundary producing a spurious one) could leave the SERVER believing this
/// device left for good, silently failing every check-in from then on with
/// "location not confirmed", even after the person came back and even though
/// the device's own last-known state (and the person standing in the
/// building) says otherwise — recoverable only by GPS happening to get a
/// clean fix indoors, which is exactly the unreliable step being routed
/// around here.
Future<bool> _refreshCurrentPosition(List<dynamic> locations) async {
  try {
    Position position;
    try {
      // This runs on EVERY app open/resume (via OfficeGeofenceService.start()
      // from AppProvider.refreshNetworkAndSession), not just once — a slow/
      // cold GPS fix here was the single biggest contributor to "the app
      // feels slow to open". Capped lower than before since the fallback
      // right below (getLastKnownPosition) already exists for exactly this
      // case; a stale-but-real last-known fix beats waiting through most of
      // a long timeout just to fall back to the same thing anyway.
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return await _reassertCachedStatus();
      position = last;
    }

    final insideZoneIds = <String>{};
    for (final raw in locations) {
      final location = raw as Map<String, dynamic>;
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        (location['latitude'] as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      );
      if (distance <= (location['radiusMeters'] as num).toDouble()) {
        insideZoneIds.add(location['id'].toString());
      }
    }
    await _reportInsideStatus(insideZoneIds);
    return insideZoneIds.isNotEmpty;
  } catch (_) {
    // Best-effort — the geofence transition callback still covers things
    // from here on even if this one-off read failed (no permission yet, GPS
    // cold). Trust (and re-send) the last known status rather than blocking.
    return await _reassertCachedStatus();
  }
}

/// Re-sends whatever zone membership was already on record — to the server
/// too, not just the local check — without needing a fresh GPS fix. Safe to
/// call anytime: if the cached set is genuinely empty (device really isn't
/// near any zone, or never has been), this just re-confirms "outside" again,
/// which is a no-op either way.
Future<bool> _reassertCachedStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final zones = (prefs.getStringList(_zonesInsideKey) ?? []).toSet();
  await _reportInsideStatus(zones);
  return zones.isNotEmpty;
}

/// A best-effort fresh GPS read to confirm a native EXIT trigger is real,
/// checked against the SPECIFIC zone that just fired it. Returns true
/// (trust the OS) if GPS can't produce a fix at all right now — see the
/// caller's note on why silence must never override a real signal.
Future<bool> _isActuallyInside(ActiveGeofence geofence) async {
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
    );
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      geofence.location.latitude,
      geofence.location.longitude,
    );
    return distance <= geofence.radiusMeters;
  } catch (_) {
    return true;
  }
}

/// The geofence transition callback — native_geofence spins up a fresh
/// headless Flutter engine to run this, so (like the old
/// officeGeofenceCallbackDispatcher) it must be a top-level function with
/// this exact annotation, and it only ever touches its own fresh service
/// instances.
///
/// Briefly promotes to a foreground service for the handful of seconds this
/// needs: Android hides the real Wi-Fi BSSID from a background-priority
/// process, so confirming the router on arrival/departure still needs *some*
/// foreground promotion — just not an all-day one like before. This is
/// exactly the "tied to a discrete, system-triggered event, stops right
/// after" pattern Google Play's foreground-service policy requires.
@pragma('vm:entry-point')
Future<void> officeGeofenceCallback(GeofenceCallbackParams params) async {
  try {
    // Isolate-local — native_geofence's fresh headless engine has none of the
    // main app's already-resolved state. See RemoteConfigService.
    await RemoteConfigService.init();

    final storage = SecureStorageService();
    final token = await storage.readToken();
    if (token == null) return; // Nobody logged in on this device.

    final zoneId = params.geofences.isNotEmpty ? params.geofences.first.id : null;
    if (zoneId == null) return;

    if (params.event == GeofenceEvent.enter) {
      try {
        await NativeGeofenceBackgroundManager.instance.promoteToForeground();
      } catch (_) {}
      // _updateZoneMembership starts the backup verification loop itself
      // once it sees this zone in the "inside" set, and runAttendanceCheck
      // does the actual Wi-Fi confirmation + check-in while still promoted.
      await _updateZoneMembership(zoneId, true);
      await runAttendanceCheck();
    } else if (params.event == GeofenceEvent.exit) {
      try {
        await NativeGeofenceBackgroundManager.instance.promoteToForeground();
      } catch (_) {}

      // Android's GPS-based geofencing can fire a real EXIT callback from
      // nothing more than indoor GPS drift right at the boundary — someone
      // standing still at their desk, never actually leaving — and unlike a
      // Wi-Fi drop (which already gets a 15-minute grace period before it's
      // trusted, see wifiDisconnectGracePeriod in attendance_check_worker.dart),
      // this used to check the person out INSTANTLY on the OS's word alone,
      // with zero confirmation. One fresh GPS fix, checked against this same
      // zone right now, catches "that was just noise" before it ever touches
      // the attendance record. Errs toward TRUSTING the native EXIT when GPS
      // has nothing to offer (no fix at all) — a missing reading can't prove
      // the OS wrong, and a real departure must never be stuck open forever
      // just because GPS happened to be unavailable at this exact moment.
      final reallyLeft = !(await _isActuallyInside(params.geofences.first));
      if (!reallyLeft) return;

      await _updateZoneMembership(zoneId, false);
      // Belt-and-suspenders: record the departure directly too, in case the
      // membership update above didn't also mean this device saw it as
      // "left" for attendance purposes.
      final api = ApiClient(storage);
      final auth = AuthService(api, storage);
      await AttendanceAwayTracker.noteDeparture();
      await auth.markCheckoutSilently();
    }
  } catch (_) {
    // A geofence callback throwing must never crash this isolate — the next
    // transition (or the 15-minute backup loop) tries again.
  } finally {
    try {
      await NativeGeofenceBackgroundManager.instance.demoteToBackground();
    } catch (_) {}
  }
}

/// Wakes/stops the 15-minute backup verification loop based on Android's own
/// OS-level geofence monitoring — a second, independent signal alongside the
/// backup loop's own scheduling, not a replacement for it. Geofencing
/// survives the app being fully closed far more reliably than any app-level
/// background loop can, since it's backed by the device's own location
/// hardware rather than a process this app has to keep alive itself, and
/// (unlike the old design) never keeps its own service running just to wait.
class OfficeGeofenceService {
  /// Location permissions are requested up front by PermissionOnboardingScreen,
  /// not here — requesting them from this and from elsewhere independently
  /// was a real race (Android only shows one permission dialog at a time),
  /// and this is called from headless background isolates (the FCM watchdog,
  /// the geofence callback itself) where a permission dialog has no
  /// foreground Activity to appear in anyway. If location isn't granted yet,
  /// geofencing just won't have anything useful to report.
  /// Returns true only if this call's fresh GPS read confirms the device is
  /// currently inside an active office zone.
  static Future<bool> start() async {
    if (kIsWeb) return false;
    // Self-contained regardless of which isolate called this (the main app,
    // or the FCM background handler) — see RemoteConfigService. Cheap to
    // call again even when a caller already ran it: minimumFetchInterval
    // throttles the actual network fetch, this just re-applies whatever's
    // already resolved/cached.
    await RemoteConfigService.init();

    try {
      await NativeGeofenceManager.instance.initialize();
    } catch (_) {}

    final locations = await _registerZones();
    // A transient failure fetching the locations list (no data connection
    // yet, a momentary API hiccup, ...) isn't proof the device left the
    // office — same reasoning as the GPS fallback in
    // _refreshCurrentPosition, and equally reachable on every app open. Also
    // re-sync the server's copy of this flag, not just the local one — see
    // _reassertCachedStatus.
    if (locations == null) return await _reassertCachedStatus();
    return await _refreshCurrentPosition(locations);
  }

  /// Re-fetches the current set of approved locations and replaces whatever
  /// geofences were previously registered — safe to call again any time an
  /// admin might have changed them (e.g. right after login). Returns the
  /// fetched locations (or null on failure) so the caller can also do an
  /// immediate position check against the same list without fetching twice.
  static Future<List<dynamic>?> _registerZones() async {
    try {
      final storage = SecureStorageService();
      final api = ApiClient(storage);
      final locations = await api.getList(ApiConfig.geofenceLocations);

      // Android re-fires the initialTrigger (ENTER) EVERY time a geofence is
      // (re-)registered while the device is already standing inside it — so
      // blindly removing and recreating on every call (an FCM wake ping, an
      // app open, ...) made the brief foreground-service promotion for the
      // Wi-Fi check flap on/off in a tight loop for anyone sitting still in
      // an office. Skip the remove/recreate entirely when the already-registered
      // set matches the server's set exactly; only an actual change (admin
      // edited a location, or registration genuinely went missing) needs it.
      final desiredIds = locations.map((raw) => (raw as Map<String, dynamic>)['id'].toString()).toSet();
      final currentIds = (await NativeGeofenceManager.instance.getRegisteredGeofenceIds()).toSet();
      if (desiredIds.length == currentIds.length && desiredIds.containsAll(currentIds)) {
        return locations;
      }

      await NativeGeofenceManager.instance.removeAllGeofences();
      for (final raw in locations) {
        final location = raw as Map<String, dynamic>;
        final zone = Geofence(
          id: location['id'].toString(),
          location: Location(
            latitude: (location['latitude'] as num).toDouble(),
            longitude: (location['longitude'] as num).toDouble(),
          ),
          radiusMeters: (location['radiusMeters'] as num).toDouble(),
          triggers: const {GeofenceEvent.enter, GeofenceEvent.exit},
          iosSettings: const IosGeofenceSettings(initialTrigger: false),
          androidSettings: const AndroidGeofenceSettings(
            initialTriggers: {GeofenceEvent.enter},
            // Not letting Android auto-remove this after a week — a zone
            // stays registered indefinitely until an admin actually
            // changes it and this re-registers with the new list.
            expiration: Duration(days: 365),
            notificationResponsiveness: Duration(minutes: 2),
          ),
        );
        await NativeGeofenceManager.instance.createGeofence(zone, officeGeofenceCallback);
      }
      return locations;
    } catch (_) {
      // Best-effort — the Wi-Fi-based check-in/out flow works fine on its
      // own even with no geofences registered.
      return null;
    }
  }

  static Future<void> stop() async {
    try {
      await NativeGeofenceManager.instance.removeAllGeofences();
      await cancelAttendancePeriodicCheck();
      await NotificationService().clearAll();
    } catch (_) {}
  }
}
