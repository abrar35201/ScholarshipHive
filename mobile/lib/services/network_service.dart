import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/api_config.dart';
import '../core/api_exception.dart';
import 'api_client.dart';

/// Android's own privacy redaction for a backgrounded app's Wi-Fi read.
const String _maskedBssid = '02:00:00:00:00:00';

class NetworkCheckOutcome {
  final bool allowed;
  final String message;
  final String? bssid;
  final String? ssid;
  final bool geofenceRequired;

  /// True only when the check-network call itself failed to reach the server
  /// (timeout, no connectivity, 5xx) — as opposed to the server responding
  /// normally with "not an approved network". Callers that treat `!allowed`
  /// as "the user left the building" (e.g. auto checkout) must not do so when
  /// this is true, since a transient server hiccup would otherwise look
  /// identical to actually leaving and check someone out who never left.
  final bool unreachable;

  /// True when Android redacted the BSSID because the app isn't in the
  /// foreground right now — this still means a Wi-Fi connection is active,
  /// just not which one, so (like [unreachable]) it must not be treated as
  /// "left the network": that would auto-checkout someone who never moved,
  /// purely because Android started hiding the value after some time in
  /// the background.
  final bool ambiguous;

  NetworkCheckOutcome({
    required this.allowed,
    required this.message,
    this.bssid,
    this.ssid,
    this.geofenceRequired = true,
    this.unreachable = false,
    this.ambiguous = false,
  });
}

class NetworkService {
  final ApiClient _api;
  final _networkInfo = NetworkInfo();

  NetworkService(this._api);

  Future<bool> ensurePermissions() async {
    // Browsers do not expose Android's runtime location permission API.
    if (kIsWeb) return false;
    // A background WorkManager isolate has no Activity to attach a permission
    // dialog to, so only prompt when we don't already know the answer —
    // by the time the background task runs, the foreground app has normally
    // already been granted this once.
    final current = await Permission.locationWhenInUse.status;
    if (current.isGranted) return true;
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  /// Used by the foreground "add current router" flow, where the app is
  /// always in the foreground so the masked-BSSID case doesn't apply.
  Future<String?> getDeviceBssid() async {
    if (kIsWeb) return null;
    try {
      final bssid = await _networkInfo.getWifiBSSID();
      if (bssid == null || bssid.isEmpty || bssid == _maskedBssid) {
        return null;
      }
      return bssid;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getDeviceSsid() async {
    if (kIsWeb) return null;
    try {
      final ssid = await _networkInfo.getWifiName();
      if (ssid == null || ssid.isEmpty) return null;
      // Android often wraps the SSID in quotes, e.g. "MyNetwork".
      return ssid.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }

  /// With several approved routers on site, a phone roams from one to another
  /// the moment the first one's signal weakens — completely normal, expected
  /// behavior, not the phone leaving the building. That handoff passes
  /// through a brief in-between moment where the BSSID is momentarily
  /// unreadable or the connectivity API hasn't caught up yet; retrying a few
  /// times over a couple of seconds rides through that instead of mistaking
  /// the handoff itself for "left the network".
  Future<NetworkCheckOutcome> checkNetwork() async {
    if (kIsWeb) {
      return NetworkCheckOutcome(
        allowed: false,
        message: 'Browser Wi-Fi verification is unavailable. Use the Android app to verify attendance.',
      );
    }
    var outcome = await _checkNetworkOnce();
    var attempt = 0;
    while (!outcome.allowed && (outcome.ambiguous || outcome.unreachable) && attempt < 3) {
      await Future.delayed(const Duration(milliseconds: 1200));
      outcome = await _checkNetworkOnce();
      attempt++;
    }
    return outcome;
  }

  Future<NetworkCheckOutcome> _checkNetworkOnce() async {
    final hasPermission = await ensurePermissions();
    if (!hasPermission) {
      return NetworkCheckOutcome(
        allowed: false,
        message: 'Location permission is required to verify your Wi-Fi network. Please grant it in app settings.',
      );
    }

    final connectivity = await Connectivity().checkConnectivity();
    final onWifi = connectivity.contains(ConnectivityResult.wifi);

    String? rawBssid;
    try {
      rawBssid = await _networkInfo.getWifiBSSID();
    } catch (_) {
      rawBssid = null;
    }

    if (rawBssid == _maskedBssid) {
      return NetworkCheckOutcome(
        allowed: false,
        message: 'Could not verify your Wi-Fi network right now.',
        ambiguous: true,
      );
    }

    if (rawBssid == null || rawBssid.isEmpty) {
      return NetworkCheckOutcome(
        allowed: false,
        message: 'Could not detect your Wi-Fi network. Make sure Wi-Fi and Location are turned on, then try again.',
        // Android still reporting an active Wi-Fi connection while the BSSID
        // itself isn't readable yet is exactly what a router-to-router
        // handoff looks like mid-flight — not actually losing Wi-Fi.
        ambiguous: onWifi,
      );
    }

    // Android's WifiManager can keep returning the *last* connection's BSSID
    // for a while after Wi-Fi is actually disabled or disconnected — trusting
    // that alone would let a phone that lost Wi-Fi but still has mobile data
    // keep "verifying" itself using a stale value. Cross-checking the current
    // transport closes that gap — but only when it can positively confirm a
    // non-Wi-Fi transport; an inconclusive/empty connectivity read must not
    // override a BSSID we did just successfully read.
    if (connectivity.isNotEmpty && !onWifi) {
      return NetworkCheckOutcome(
        allowed: false,
        message: 'Could not detect your Wi-Fi network. Make sure Wi-Fi and Location are turned on, then try again.',
      );
    }

    final bssid = rawBssid;
    final ssid = await getDeviceSsid();

    try {
      final result = await _api.post(ApiConfig.checkNetwork, {'bssid': bssid, 'ssid': ssid});
      return NetworkCheckOutcome(
        allowed: result['allowed'] == true,
        message: result['message'] as String? ?? '',
        bssid: bssid,
        ssid: ssid,
        geofenceRequired: result['geofenceRequired'] != false,
      );
    } on ApiException catch (e) {
      return NetworkCheckOutcome(allowed: false, message: e.message, bssid: bssid, ssid: ssid, unreachable: true);
    }
  }
}
