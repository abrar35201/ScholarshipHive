import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'providers/app_provider.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/announcements/announcement_login_popup.dart';
import 'screens/home/home_screen.dart';
import 'screens/reception/reception_screen.dart';
import 'screens/department/department_team_screen.dart';
import 'screens/country/country_head_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/network_error/network_error_screen.dart';
import 'screens/onboarding/permission_onboarding_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/attendance_check_worker.dart';
import 'services/fcm_service.dart';
import 'services/remote_config_service.dart';
import 'package:workmanager/workmanager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // None of these three blocks the very first frame — every one of them only
  // matters for something that happens well after the splash screen is
  // already on screen (a scheduled background task, a registered FCM
  // listener, a resolved server URL), never for rendering the UI itself.
  // These three used to run one after another (await, await, await) BEFORE
  // runApp() — three sequential native inits standing between a cold tap on
  // the icon and the very first pixel this app ever draws, which is exactly
  // what made "app opening" feel slow. Racing them in the background instead
  // means the splash screen shows immediately, and by the time any of these
  // three is actually needed (a real background task gets scheduled, a real
  // network call goes out), they've almost always already finished anyway.
  if (!kIsWeb) {
    unawaited(RemoteConfigService.init());
    unawaited(Workmanager().initialize(workmanagerCallbackDispatcher));
    unawaited(FcmService.init());
  }
  runApp(const ScholarshipHiveApp());
}

class ScholarshipHiveApp extends StatelessWidget {
  const ScholarshipHiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: 'ScholarshipHive',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const RootRouter(),
      ),
    );
  }
}

/// Network/session state is otherwise only checked once, at cold start
/// (see SplashScreen.initState) — bringing the app back to the foreground
/// (unlocking the phone, switching back from another app) never re-verified
/// it on its own. That's what made reconnecting Wi-Fi after a drop look like
/// it "didn't log back in": the UI was just showing whatever stale stage it
/// was in from before the drop until the person forced a fresh cold start.
/// Re-checking on every resume keeps it honest.
class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final provider = context.read<AppProvider>();
    // Nothing to re-sync on the login screen (no session to refresh yet), or
    // while a check/login is already in flight (the very first resume right
    // after cold start, while bootstrap() is still running, or mid-login).
    if (provider.stage == AppStage.loggedOut || provider.stage == AppStage.checkingNetwork || provider.isBusy) {
      return;
    }
    // Never the loading-screen variant here: this fires on every single
    // resume — a notification tray pull-down, a permission dialog closing,
    // switching back from another app, even the system briefly taking focus
    // — and showing the splash screen doesn't just re-check quietly, it
    // instantly replaces whatever real screen was on-screen a moment ago
    // (the admin control panel, a report, anything) with a full-screen
    // loader. That's what read as "the app keeps restarting" even though
    // nothing was actually lost — see refreshNetworkAndSession's
    // showLoadingScreen parameter.
    provider.refreshNetworkAndSession(showLoadingScreen: false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    switch (provider.stage) {
      case AppStage.checkingNetwork:
        return const SplashScreen();
      case AppStage.networkDenied:
        return const NetworkErrorScreen();
      case AppStage.loggedOut:
        return const LoginScreen();
      case AppStage.loggedIn:
        return const _LoggedInGate();
    }
  }
}

/// Shows the normal Home/AdminHome screen immediately — the permission
/// onboarding wizard runs in the background and, if needed, presents itself
/// on TOP of that (a pushed route) rather than gating it behind its own
/// loading screen. Gating it used to insert a visible extra splash flash
/// between login and the real screen on every single app open, for everyone,
/// just to cover the rare case where the wizard is actually needed.
class _LoggedInGate extends StatefulWidget {
  const _LoggedInGate();

  @override
  State<_LoggedInGate> createState() => _LoggedInGateState();
}

class _LoggedInGateState extends State<_LoggedInGate> {
  @override
  void initState() {
    super.initState();
    _checkPermissionOnboarding().then((_) async {
      // Login notices are shown after first-login permission guidance.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) await AnnouncementLoginPopup.showIfNeeded(context);
    });
    _checkDeviceSwitchNotice();
  }

  /// A device that just took over from a different account (see
  /// AuthController.Login) has already been silently reconciled on the
  /// backend — the other person's open attendance was closed out for them —
  /// but the person doing the switching would otherwise have no way to know
  /// that happened at all. One-time, since consumeDeviceSwitchNotice() clears
  /// it on read; a later rebuild of this same gate won't show it again.
  void _checkDeviceSwitchNotice() {
    final notice = context.read<AppProvider>().consumeDeviceSwitchNotice();
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Heads up'),
          content: Text(notice),
          actions: [TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Got it'))],
        ),
      );
    });
  }

  Future<void> _checkPermissionOnboarding() async {
    if (kIsWeb || context.read<AppProvider>().currentUser?.role == 'Receptionist') return;
    final needs = await PermissionOnboardingScreen.shouldShow();
    if (needs && mounted) {
      // The screen pops itself (with its own context) when the wizard
      // finishes — onDone is just a hook for any extra follow-up, not the
      // pop itself. This state's own context can go stale by then (e.g. if
      // an ancestor rebuilds while the wizard is still on top), and using it
      // for the pop was throwing a silent "Null check operator used on a
      // null value" that left the wizard stuck on its last step forever.
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PermissionOnboardingScreen(onDone: () {})));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    if (provider.currentUser?.role == 'Receptionist') return const ReceptionScreen();
    if (provider.currentUser?.role == 'CountryHead') return const CountryHeadScreen();
    if (['HeadOfCounselors','HeadOfMarketing','HeadOfProcessing'].contains(provider.currentUser?.role)) return const DepartmentTeamScreen();
    return provider.isAdmin ? const AdminHomeScreen() : const HomeScreen();
  }
}
