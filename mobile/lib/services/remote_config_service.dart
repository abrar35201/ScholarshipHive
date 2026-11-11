import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../core/api_config.dart';

/// The one thing standing between "the backend moved or died" and "every
/// already-installed phone is stranded with no way to find out" — see
/// ApiConfig's doc comment for the full story (this is exactly what happened
/// when the old Railway account was suspended: every phone still pointed at
/// the dead URL, and the self-update check itself lived on that same dead
/// server, so nothing could ever recover on its own — the only fix left was
/// manually re-sideloading a new APK onto every phone).
///
/// Firebase Remote Config is hosted entirely separately from wherever the
/// backend happens to live this month, and caches its last successfully-
/// fetched value on-device by default — so even a phone with no network
/// right now still uses whatever server URL a PAST successful fetch left
/// behind, rather than ever silently reverting to the value compiled into
/// that particular APK build. From here on, recovering from a backend move
/// is: update one Remote Config value in the Firebase console — no new APK,
/// no re-sideloading anything.
///
/// Self-contained and safe to call from any isolate (the main app, or any of
/// the three background entry points — WorkManager, the geofence callback,
/// the FCM background handler) without the caller needing to have already
/// initialized Firebase itself.
class RemoteConfigService {
  static Future<void> init() async {
    // This app has native Firebase configuration only. Web Firebase needs a
    // separate set of options, so Chrome keeps the API-configured URL.
    if (kIsWeb) return;
    // A local debug APK may pass API_SERVER_URL to reach a developer's LAN
    // backend. Do not let the production Remote Config value replace it.
    if (kDebugMode) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          // This runs on the critical path of a background check-in (a real
          // office arrival, where every second matters) — capped low on
          // purpose so a slow/flaky connection can't stall that. The Remote
          // Config SDK's own on-device cache (persists across isolates/app
          // restarts — this is real disk state, not per-isolate memory) makes
          // this timeout matter only on a genuinely fresh fetch; every call
          // within [minimumFetchInterval] of the last successful one resolves
          // from cache in milliseconds regardless of network speed.
          fetchTimeout: const Duration(seconds: 4),
          // Remote Config itself still enforces this as a floor even if asked
          // to fetch more often — the point of this value isn't rate-limiting
          // (the compiled-in default already covers the ordinary case fine),
          // it's the safety net for the rare day the backend actually moves.
          minimumFetchInterval: const Duration(minutes: 30),
        ),
      );
      await remoteConfig.setDefaults({'server_url': ApiConfig.serverUrl});

      await remoteConfig.fetchAndActivate();
      ApiConfig.applyRemoteServerUrl(remoteConfig.getString('server_url'));
    } catch (_) {
      // Best-effort — a failed fetch (no network yet, Remote Config
      // unreachable, this isolate has nothing to init with) just means
      // sticking with the compiled-in default, or whatever an earlier
      // successful fetch already cached on this device.
    }
  }
}
