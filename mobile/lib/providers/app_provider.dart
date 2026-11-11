import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/api_config.dart';
import '../core/api_exception.dart';
import '../models/user.dart';
import '../services/admin_api_service.dart';
import '../services/api_client.dart';
import '../services/attendance_service.dart';
import '../services/attendance_away_tracker.dart';
import '../services/audit_report_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_lock_service.dart';
import '../services/chat_service.dart';
import '../services/device_id_service.dart';
import '../services/fcm_service.dart';
import '../services/network_service.dart';
import '../services/notification_service.dart';
import '../services/office_geofence_service.dart';
import '../services/realtime_service.dart';
import '../services/report_service.dart';
import '../services/secure_storage_service.dart';

enum AppStage { checkingNetwork, networkDenied, loggedOut, loggedIn }

class AppProvider extends ChangeNotifier {
  bool _remoteAdminSession = false;
  int _sessionRevision = 0;
  late final SecureStorageService _storage;
  late final ApiClient _api;
  ApiClient get api => _api;
  late final NetworkService networkService;
  late final AuthService authService;
  late final ReportService reportService;
  late final AdminApiService adminApiService;
  late final ChatService chatService;
  late final AuditReportService auditReportService;
  late final AttendanceService attendanceService;
  late final NotificationService notificationService;
  late final RealtimeService _realtimeService;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _backgroundMonitoringInitialized = false;
  bool _realtimeStarted = false;

  AppProvider() {
    _storage = SecureStorageService();
    _api = ApiClient(_storage);
    networkService = NetworkService(_api);
    authService = AuthService(_api, _storage);
    reportService = ReportService(_api);
    adminApiService = AdminApiService(_api);
    chatService = ChatService(_api);
    auditReportService = AuditReportService(_api);
    attendanceService = AttendanceService(_api);
    notificationService = NotificationService();
    _realtimeService = RealtimeService(_storage);

    // Network/session state was otherwise only (re-)checked at cold start or
    // on app resume — someone toggling Wi-Fi/airplane mode while just sitting
    // on the app never triggered a re-check on its own, so reconnecting could
    // look like it silently never logged back in. This reacts the moment
    // Android reports connectivity back, not just on the next app open.
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((transports) {
      // Android emits this transition even when *all* data is off. Save the
      // departure locally first; a later reconnect can reconcile it securely.
      if (!kIsWeb && stage == AppStage.loggedIn && currentUser != null &&
          !_isPrimaryAdmin && !transports.contains(ConnectivityResult.wifi)) {
        unawaited(AttendanceAwayTracker.noteDeparture());
        unawaited(authService.markCheckoutSilently());
      }
      if (!kIsWeb && transports.contains(ConnectivityResult.wifi) &&
          currentUser != null && !_isPrimaryAdmin && !isBusy) {
        unawaited(refreshNetworkAndSession(showLoadingScreen: false));
      } else if (stage == AppStage.networkDenied && !isBusy) {
        unawaited(refreshNetworkAndSession());
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Bumped on every live push from the server; admin tabs watch this and refetch
  /// their own data when it changes. Only Admin sessions open this connection —
  /// Employees never need it, so it doesn't cost them a persistent connection.
  int realtimeTick = 0;

  Future<void> _maybeStartRealtime() async {
    if (_realtimeStarted || !isAdmin) return;
    _realtimeStarted = true;
    await _realtimeService.start(
      onChanged: (_) {
        realtimeTick++;
        notifyListeners();
      },
    );
  }

  /// Wires up the local "welcome" notification's tap handler, and — if
  /// someone's already logged in on this device — refreshes the FCM token
  /// registration. Starting geofence monitoring itself now lives inside
  /// refreshNetworkAndSession(), since that's the one place that needs its
  /// result (both to gate check-in and to decide whether checking Wi-Fi is
  /// even worth doing) — duplicating the call here too would just mean
  /// fetching zones and taking a GPS reading twice on every cold start.
  /// Only needs to run once; safe to call regardless of login state.
  ///
  /// notificationService.init() is deliberately NOT awaited: on at least one
  /// device its notification-permission request never resolved, which — since
  /// bootstrap() awaits this whole function before ever reaching the login
  /// screen — left a fresh install stuck on the splash screen forever, unable
  /// to log in at all. Nothing about reaching the login screen actually
  /// depends on notifications being ready yet, so this no longer gets to
  /// block that.
  Future<void> initBackgroundMonitoring() async {
    if (_backgroundMonitoringInitialized) return;
    _backgroundMonitoringInitialized = true;

    if (!kIsWeb) {
      unawaited(
        notificationService.init(
          onTapped: () {
            refreshNetworkAndSession();
          },
        ),
      );
    }

    if (await authService.hasStoredToken()) {
      unawaited(FcmService.registerToken());
    }
  }

  // Auditor has the same broad access as Admin — the same admin console just
  // works for both, since every admin-only endpoint accepts both roles too.
  bool get _isPrimaryAdmin => currentUser?.role == 'Admin' &&
      currentUser?.username.toLowerCase() == 'admin';
  bool get _requiresAttendance => currentUser != null && !_isPrimaryAdmin;
  bool get isAdmin => ['Admin','Auditor','SuperAdmin','Owner','CountryHead','HeadOfMarketing','HeadOfProcessing'].contains(currentUser?.role);

  AppStage stage = AppStage.checkingNetwork;
  String? networkMessage;

  /// Machine-readable reason behind [networkMessage], if any — e.g.
  /// "location_not_confirmed" — so NetworkErrorScreen can show a location-
  /// specific icon/title instead of always looking like a Wi-Fi problem.
  String? networkErrorCode;
  String? lastUsername;

  AppUser? currentUser;

  /// Set only right after a login that just took over this device from a
  /// different account (see AuthController.Login) — read this via
  /// [consumeDeviceSwitchNotice], not directly, so it only ever gets shown
  /// once instead of reappearing on every rebuild that happens to read it.
  String? deviceSwitchNotice;

  /// One-time read: returns the pending notice (if any) and clears it in the
  /// same step, so whoever displays it is guaranteed to be the only one who
  /// does.
  String? consumeDeviceSwitchNotice() {
    final notice = deviceSwitchNotice;
    deviceSwitchNotice = null;
    return notice;
  }

  /// Set when a borrowed-device session got force-ended by Checkin's
  /// device_borrow_expired check (see AuthController.Checkin) — the login
  /// screen shows this once via [consumeForcedLogoutNotice] so whoever's
  /// looking at it understands why they're suddenly signed out instead of
  /// assuming the app just broke.
  String? forcedLogoutNotice;

  String? consumeForcedLogoutNotice() {
    final notice = forcedLogoutNotice;
    forcedLogoutNotice = null;
    return notice;
  }

  bool reportSubmitted = false;
  bool justMarkedAttendance = false;
  DateTime? todayCheckInTime;
  DateTime? todayCheckOutTime;

  bool isBusy = false;
  String? errorMessage;

  Future<void> bootstrap() async {
    lastUsername = await _storage.readLastUsername();
    // Old builds could save a remote session for a Head or secondary Admin.
    // Only the seeded primary Admin may retain the remote exception.
    _remoteAdminSession = (await _storage.readRemoteAdminSession()) &&
        lastUsername?.toLowerCase() == 'admin';
    await _storage.saveRemoteAdminSession(_remoteAdminSession);
    await initBackgroundMonitoring();
    await refreshNetworkAndSession();
  }

  /// [showLoadingScreen] controls whether this flips `stage` to
  /// checkingNetwork up front — which is what makes RootRouter swap the
  /// current screen for the splash screen. True (the default) is right for a
  /// cold start, where there's nothing real on screen to interrupt yet.
  /// False is for a resume-triggered re-check (see RootRouter's
  /// didChangeAppLifecycleState): the person was already looking at a real
  /// screen a moment ago, and flashing the splash screen in front of it on
  /// every single resume — a notification, a permission dialog, switching
  /// back from another app — is exactly what made the app look like it kept
  /// "restarting" even though nothing was actually lost. Either way, a
  /// genuine problem this finds (network denied, session invalid) still
  /// shows its own real screen below — that's not a spurious interruption,
  /// that's this doing its job.
  Future<void> refreshNetworkAndSession({bool showLoadingScreen = true}) async {
    final revision = _sessionRevision;
    if (showLoadingScreen) {
      stage = AppStage.checkingNetwork;
      notifyListeners();
    }

    final hasToken = await authService.hasStoredToken();
    if (revision != _sessionRevision) return;
    if (!hasToken) {
      stage = AppStage.loggedOut;
      notifyListeners();
      return;
    }

    // A local Chrome admin session cannot use native Wi-Fi/geofence APIs.
    // The backend accepts this flag only for Admin/Auditor accounts on a
    // loopback origin in Development mode, and it does not create attendance.
    final developmentBrowserAdmin = ApiConfig.useDevelopmentBrowserAdminAuth || _remoteAdminSession;

    // The backend's network response carries the server-controlled geofence
    // requirement. Production and older servers default to requiring it;
    // local Development can temporarily use approved Wi-Fi alone.
    NetworkCheckOutcome? netOutcome;
    if (!developmentBrowserAdmin) {
      netOutcome = await networkService.checkNetwork();
      if (netOutcome.geofenceRequired) {
        bool insideGeofence;
        try {
          // Bounded defensively — this touches native plugin calls, GPS, and a
          // network fetch, and nothing about showing an error screen (which is
          // exactly what happens next if this comes back false) should ever be
          // able to hang indefinitely waiting on any one of them.
          insideGeofence = await OfficeGeofenceService.start().timeout(const Duration(seconds: 15));
        } catch (_) {
          insideGeofence = false;
        }
        if (!insideGeofence) {
          networkMessage =
              'Location isn\'t confirmed yet — make sure location access is set to "Allow all the time" for ScholarshipHive, then try again.';
          networkErrorCode = 'location_not_confirmed';
          stage = AppStage.networkDenied;
          notifyListeners();
          return;
        }
      } else {
        // Keep the existing background geofence/wake monitoring alive in
        // Development; it simply does not gate the Wi-Fi-based attendance flow.
        unawaited(OfficeGeofenceService.start());
      }

      if (!netOutcome.allowed || netOutcome.bssid == null) {
        networkMessage = netOutcome.message;
        networkErrorCode = null;
        stage = AppStage.networkDenied;
        notifyListeners();
        return;
      }
    }

    try {
      // No password needed here — being on the approved network plus the token
      // already stored from a previous login is enough to silently re-authenticate
      // and mark today's attendance if it hasn't been marked yet.
      final result = developmentBrowserAdmin
          ? await authService.checkin(ApiConfig.developmentBrowserAdminBssid, developmentBrowserAdmin: true)
          : await _checkinWithRetry(netOutcome!.bssid!, netOutcome.ssid);
      if (revision != _sessionRevision) return; // A logout happened while this request was in flight.
      _remoteAdminSession = developmentBrowserAdmin && result.user.role == 'Admin' && result.user.username.toLowerCase() == 'admin';
      await _storage.saveRemoteAdminSession(_remoteAdminSession);
      if (revision != _sessionRevision) return;
      currentUser = result.user;
      reportSubmitted = result.reportSubmitted;
      justMarkedAttendance = result.attendanceMarked;
      todayCheckInTime = result.checkInTime;
      todayCheckOutTime = result.checkOutTime;
      networkErrorCode = null;
      stage = AppStage.loggedIn;
      unawaited(_maybeStartRealtime());
    } on ApiException catch (e) {
      if (revision != _sessionRevision) return;
      if (e.statusCode == 401) {
        // The token itself is genuinely invalid (e.g. account deactivated) —
        // this is the one case where actually signing out is correct.
        await authService.forceClearSession();
        stage = AppStage.loggedOut;
      } else if (e.code == 'device_borrow_expired') {
        // A same-day-only borrowed session (see AuthController.Checkin) past its
        // grace — end it the same way a 401 does, but also drop the stored
        // username so the login screen doesn't pre-fill the BORROWER's name for
        // whoever picks this device up next (most likely its actual owner).
        await authService.forceClearSession();
        await _storage.clearLastUsername();
        lastUsername = null;
        forcedLogoutNotice = e.message;
        stage = AppStage.loggedOut;
      } else {
        // Everything else — a server blip, or the same-building router handoff
        // the backend hasn't caught up on yet — is transient. Destroying a
        // valid session over it is exactly what was forcing everyone back to
        // the login screen; show a retryable screen and keep the token instead.
        networkMessage = e.message;
        networkErrorCode = e.code;
        stage = AppStage.networkDenied;
      }
    } catch (_) {
      if (revision != _sessionRevision) return;
      networkMessage = 'Could not reach the server. Please try again.';
      networkErrorCode = null;
      stage = AppStage.networkDenied;
    }
    notifyListeners();
  }

  /// Roaming between two approved routers can make a single checkin attempt
  /// land in the brief window before the backend's own network check has
  /// caught up on the handoff — retrying a couple of times rides through
  /// that instead of treating it as a real failure.
  Future<LoginResult> _checkinWithRetry(String bssid, String? ssid) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await authService.checkin(bssid, ssid: ssid);
      } on ApiException catch (e) {
        // Neither is transient — retrying rides through a real router handoff, not a
        // definitive rejection that a network blip will never fix on its own.
        if (e.statusCode == 401 || e.code == 'device_borrow_expired' || attempt >= 2) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }
  }

  Future<bool> register(
    String username,
    String password,
    String fullName,
    String department, {
    String shiftType = 'Day',
  }) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      final netOutcome = await networkService.checkNetwork();
      if (!netOutcome.allowed || netOutcome.bssid == null) {
        errorMessage = netOutcome.message;
        isBusy = false;
        notifyListeners();
        return false;
      }

      await authService.register(
        username: username,
        password: password,
        fullName: fullName,
        bssid: netOutcome.bssid!,
        ssid: netOutcome.ssid,
        department: department,
        shiftType: shiftType,
      );

      isBusy = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isBusy = false;
      notifyListeners();
      return false;
    }
  }

  /// A single Sign In button for every account. The server first verifies the
  /// password and returns a manager session without office Wi-Fi only for a
  /// real, approved management role. All other valid accounts must pass the
  /// existing network-restricted login path. The client never trusts a role
  /// typed into the username field.
  Future<bool> signIn(String username, String password) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await authService.remoteAdminLogin(username, password);
      currentUser = result.user;
      lastUsername = result.user.username;
      reportSubmitted = false;
      justMarkedAttendance = false;
      todayCheckInTime = result.checkInTime;
      todayCheckOutTime = null;
      _remoteAdminSession = result.user.role == 'Admin' && result.user.username.toLowerCase() == 'admin';
      await _storage.saveRemoteAdminSession(_remoteAdminSession);
      stage = AppStage.loggedIn;
      isBusy = false;
      notifyListeners();
      unawaited(_maybeStartRealtime());
      unawaited(FcmService.registerToken());
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        isBusy = false;
        notifyListeners();
        return login(username, password);
      }
      errorMessage = e.message;
      isBusy = false;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Could not reach the server. Check that the backend is running.';
      isBusy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> remoteAdminLogin(String username, String password) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await authService.remoteAdminLogin(username, password);
      currentUser = result.user;
      lastUsername = username;
      reportSubmitted = false;
      justMarkedAttendance = false;
      todayCheckInTime = result.checkInTime;
      todayCheckOutTime = null;
      _remoteAdminSession = result.user.role == 'Admin' && result.user.username.toLowerCase() == 'admin';
      await _storage.saveRemoteAdminSession(_remoteAdminSession);
      stage = AppStage.loggedIn;
      isBusy = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isBusy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> setFingerprintEnabled(String username, bool enabled) async {
    final user = currentUser;
    if (user == null || user.username.trim().toLowerCase() != username.trim().toLowerCase()) {
      throw StateError('Sign in as this account first.');
    }
    if (!enabled) {
      await BiometricLockService.disable(username);
      return;
    }
    if (!await BiometricLockService.authenticate()) {
      throw StateError('Fingerprint verification failed.');
    }
    final deviceId = await getOrCreateDeviceId();
    final credential = await authService.enrollBiometric(deviceId);
    await BiometricLockService.enroll(username, credential);
  }

  Future<bool> biometricLogin(String username) async {
    if (isBusy) return false;
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final entered = username.trim();
      if (entered.isEmpty || !await BiometricLockService.isEnabledFor(entered)) {
        errorMessage = 'Fingerprint not enabled for this username. Log in with a password first.';
        return false;
      }
      if (!await BiometricLockService.authenticate()) {
        errorMessage = 'Fingerprint not verified. Please try again or enter your password.';
        return false;
      }
      final credential = await BiometricLockService.credentialFor(entered);
      if (credential == null) {
        errorMessage = 'Fingerprint not enrolled for this account.';
        return false;
      }
      // Never reuse another account's token. Biometric credential is matched
      // against the exact entered username again by the server.
      await authService.forceClearSession();
      NetworkCheckOutcome? netOutcome;
      // Native Wi-Fi is still required for Employee attendance. Admin and
      // Reception can authenticate remotely without marking attendance.
      // Server independently enforces the role/network restriction too.
      try {
        netOutcome = await networkService.checkNetwork().timeout(const Duration(seconds: 4));
      } catch (_) {}
      final result = await authService.biometricLogin(
        username: entered, deviceId: await getOrCreateDeviceId(),
        credential: credential, bssid: netOutcome?.bssid,
        ssid: netOutcome?.ssid,
      );
      currentUser = result.user;
      lastUsername = result.user.username;
      reportSubmitted = result.reportSubmitted;
      justMarkedAttendance = result.attendanceMarked;
      todayCheckInTime = result.checkInTime;
      todayCheckOutTime = result.checkOutTime;
      _remoteAdminSession = result.user.role == 'Admin' && result.user.username.toLowerCase() == 'admin';
      await _storage.saveRemoteAdminSession(_remoteAdminSession);
      stage = AppStage.loggedIn;
      unawaited(_maybeStartRealtime());
      if (_requiresAttendance) unawaited(OfficeGeofenceService.start());
      unawaited(FcmService.registerToken());
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      return false;
    } catch (e) {
      errorMessage = 'Fingerprint login failed. Use your password and re-enroll if needed.';
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      final developmentBrowserAdmin = ApiConfig.useDevelopmentBrowserAdminAuth;
      NetworkCheckOutcome? netOutcome;
      if (!developmentBrowserAdmin) {
        netOutcome = await networkService.checkNetwork();
        if (!netOutcome.allowed || netOutcome.bssid == null) {
          errorMessage = netOutcome.message;
          isBusy = false;
          notifyListeners();
          return false;
        }
      }

      // A brand new device has no prior geofence report on record at all — that only
      // starts after a successful login — so without a location fix taken right here,
      // a first-ever login could never succeed once check-in required it. Best-effort:
      // if this fails or times out, the request still goes through with no coordinates,
      // and the server falls back to whatever (if anything) is already on record.
      Position? position;
      if (!developmentBrowserAdmin && netOutcome!.geofenceRequired) {
        try {
          // On a genuinely fresh install this permission has never been asked for at
          // all yet — the onboarding wizard only runs AFTER a successful login, so
          // without asking here too, a first-ever login could never get a location
          // fix to succeed with in the first place.
          if (!await Permission.locationWhenInUse.status.isGranted) {
            await Permission.locationWhenInUse.request();
          }
          // Capped lower than the old 15s — this already has a fallback right
          // below (getLastKnownPosition) for exactly the case where a fresh
          // fix takes too long, so there's no correctness reason to make a
          // slow/cold GPS hold up the whole login this long. A stale-but-real
          // last-known position beats waiting through most of this timeout on
          // a slow device just to fall back to the exact same thing anyway.
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
        } catch (_) {
          try {
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }
      }

      final deviceId = await getOrCreateDeviceId();
      final result = await authService.login(
        username: username,
        password: password,
        bssid: netOutcome?.bssid ?? ApiConfig.developmentBrowserAdminBssid,
        ssid: netOutcome?.ssid,
        latitude: position?.latitude,
        longitude: position?.longitude,
        deviceId: deviceId,
        developmentBrowserAdmin: developmentBrowserAdmin,
      );

      currentUser = result.user;
      // Ordinary office login is NEVER a remote-admin session, even when
      // an old version had stored that flag for this device.
      _remoteAdminSession = false;
      await _storage.saveRemoteAdminSession(false);
      reportSubmitted = result.reportSubmitted;
      justMarkedAttendance = result.attendanceMarked;
      todayCheckInTime = result.checkInTime;
      todayCheckOutTime = result.checkOutTime;
      deviceSwitchNotice = result.deviceSwitchNotice;
      lastUsername = username;
      stage = AppStage.loggedIn;
      isBusy = false;
      notifyListeners();
      unawaited(_maybeStartRealtime());
      if (!developmentBrowserAdmin && _requiresAttendance) unawaited(OfficeGeofenceService.start());
      unawaited(FcmService.registerToken());
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isBusy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changeCredentials({required String currentPassword, String? newUsername, String? newPassword}) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      final user = await authService.changeCredentials(
        currentPassword: currentPassword,
        newUsername: newUsername,
        newPassword: newPassword,
      );
      currentUser = user;
      lastUsername = user.username;
      isBusy = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isBusy = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> submitReport({
    int unreadChats = 0,
    int newLeads = 0,
    int qualifiedLeads = 0,
    int followUp = 0,
    int calls = 0,
    int potential = 0,
    int walkIns = 0,
    int conversion = 0,
    String? textContent,
    List<PlatformFile> newFiles = const [],
  }) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      await reportService.submitReport(
        unreadChats: unreadChats,
        newLeads: newLeads,
        qualifiedLeads: qualifiedLeads,
        followUp: followUp,
        calls: calls,
        potential: potential,
        walkIns: walkIns,
        conversion: conversion,
        textContent: textContent,
        newFiles: newFiles,
      );
      reportSubmitted = true;
      isBusy = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isBusy = false;
      notifyListeners();
      return false;
    }
  }

  void acknowledgeAttendanceMarked() {
    justMarkedAttendance = false;
  }

  /// Logout clears the active JWT. Account-specific biometric enrollment remains.
  Future<String?> logout() async {
    if (isBusy) return 'Please try again.';
    _sessionRevision++; // Prevent older background refreshes from restoring this account.
    isBusy = true;
    notifyListeners();
    final error = await authService.logout();
    isBusy = false;
    if (error != null) {
      notifyListeners();
      return error;
    }
    currentUser = null;
    lastUsername = null;
    await _storage.clearLastUsername();
    reportSubmitted = false;
    justMarkedAttendance = false;
    todayCheckInTime = null;
    todayCheckOutTime = null;
    deviceSwitchNotice = null;
    stage = AppStage.loggedOut;
    _remoteAdminSession = false;
    await _storage.saveRemoteAdminSession(false);
    _realtimeStarted = false;
    unawaited(_realtimeService.stop());
    unawaited(OfficeGeofenceService.stop());
    notifyListeners();
    return null;
  }

}
