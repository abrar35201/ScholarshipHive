import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pluginInitialized = false;

  static const int _monitoringNotificationId = 2001;

  /// Wires up the tap-to-open callback and requests the notification permission —
  /// only meaningful from the running app's own isolate (needs a foreground Activity
  /// to attach the tap handler to and to show the permission prompt).
  Future<void> init({required void Function() onTapped}) async {
    await _ensurePluginInitialized(onTapped: onTapped);
    await Permission.notification.request();
  }

  /// Safe to call from a background isolate (e.g. a WorkManager task), where there's
  /// no UI to prompt for permission or attach a tap handler — tapping a notification
  /// shown from there just launches the app normally instead.
  Future<void> _ensurePluginInitialized({void Function()? onTapped}) async {
    if (_pluginInitialized) return;
    _pluginInitialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onTapped == null ? null : (response) => onTapped(),
    );
  }

  Future<void> showWelcome() async {
    await _ensurePluginInitialized();
    const androidDetails = AndroidNotificationDetails(
      'daily_checkin',
      'Daily Check-In',
      channelDescription: 'Notifies you when you connect to the office network for the day',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      1001,
      'Welcome to ScholarshipHive',
      'You\'re connected — tap to check in for today.',
      details,
    );
  }

  /// The old always-on foreground service used to leave a permanent "running"
  /// notification up the whole time, which is exactly what Google Play's
  /// policy no longer allows (see office_geofence_service.dart) — the new
  /// design's checks are all brief and event-tied instead, with nothing
  /// visible left behind between them. That silence reads as "the app isn't
  /// doing anything" even when it's working correctly, which is confusing on
  /// its own right and makes a genuine failure indistinguishable from normal
  /// operation. This is a plain, silent, LOW-importance notification — not a
  /// foreground-service notification, so it doesn't reintroduce the policy
  /// problem it's meant to make visible — that just gets its timestamp
  /// refreshed on every successful background check (periodic loop, FCM
  /// watchdog nudge, or a real geofence ENTER), giving a live, glanceable
  /// "yes, this last ran at HH:MM" instead of nothing at all.
  Future<void> showMonitoringHeartbeat() async {
    await _ensurePluginInitialized();
    final timeLabel = DateFormat('hh:mm a').format(DateTime.now());
    const androidDetails = AndroidNotificationDetails(
      'scholarshiphive_status',
      'Background monitoring status',
      channelDescription: 'A quiet, persistent note confirming ScholarshipHive is still checking your location in the background. Updates silently — no sound, no popup.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: false,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _monitoringNotificationId,
      'ScholarshipHive is watching',
      'Last background check confirmed at $timeLabel.',
      details,
    );
  }

  /// Call once the device leaves every approved zone — nothing left to watch
  /// for until it's back inside one.
  Future<void> clearMonitoringHeartbeat() async {
    await _ensurePluginInitialized();
    await _plugin.cancel(_monitoringNotificationId);
  }

  /// Clears every notification this app has shown (the heartbeat AND the
  /// one-off "Welcome"/daily-check-in one, plus anything else still sitting
  /// in the tray) — called the moment the device leaves every approved zone,
  /// so nothing lingers once there's genuinely nothing left to watch for.
  /// [clearMonitoringHeartbeat] alone only ever touched its own single
  /// notification ID; this is the broader "leaving the office resets
  /// everything" sweep.
  Future<void> clearAll() async {
    await _ensurePluginInitialized();
    await _plugin.cancelAll();
  }
}
