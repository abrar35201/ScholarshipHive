import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_theme.dart';
import '../../services/oem_autostart_service.dart';
import 'oem_autostart_guide_screen.dart';

const String _completedKey = 'permission_onboarding_completed';

class _WizardStep {
  final IconData icon;
  final String title;
  final String description;
  final bool skippable;
  final String actionLabel;
  final Future<bool> Function() isGranted;
  final Future<void> Function() request;

  const _WizardStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.skippable,
    required this.actionLabel,
    required this.isGranted,
    required this.request,
  });
}

/// Walks through every permission/setting the attendance monitor depends on,
/// one at a time, in the order Android actually needs them requested in —
/// replacing what used to be several different services each independently
/// (and sometimes concurrently) firing off their own permission requests.
/// That scattered approach was exactly why "Allow all the time" location
/// sometimes never showed up: two separate services could race to request
/// location permissions at once, and Android only shows one dialog at a time.
///
/// Location (both steps) and battery-optimization exemption are NOT
/// skippable — check-in requires being at an approved office location, not
/// just on the right Wi-Fi, and without the battery exemption Android itself
/// can silently kill the background monitor before it ever gets the chance
/// to check anyone in. Neither has a safe fallback that still leaves
/// automatic check-in working.
class PermissionOnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const PermissionOnboardingScreen({super.key, required this.onDone});

  @override
  State<PermissionOnboardingScreen> createState() => _PermissionOnboardingScreenState();

  /// True if this still needs to run — either it's never been completed, or
  /// one of the two settings actual background check-in depends on has since
  /// been revoked/reset: location "all the time" (check-in fails outright
  /// without it) or battery-optimization exemption (without it, Android can —
  /// and on aggressive OEMs like Xiaomi/Oppo/Vivo, routinely does — kill the
  /// background monitor entirely, so someone arrives at the office and just
  /// never gets checked in, with no error anywhere to explain why). Both are
  /// now treated as equally mandatory rather than letting a "Skip for now" on
  /// battery optimization stay skipped forever.
  static Future<bool> shouldShow() async {
    if (!await Permission.locationAlways.status.isGranted) return true;
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) != true;
  }
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen> with WidgetsBindingObserver {
  List<_WizardStep>? _steps;
  int _index = 0;
  bool _requesting = false;
  bool? _currentGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Several steps (exact alarms, battery optimization on some OEMs, the
    // OEM autostart screen) hand off to a system Settings page instead of a
    // dialog — the only way to know what the user actually did there is to
    // re-check once they're back, and immediately move on if they granted it
    // — nobody should have to tap a separate "Continue" after already doing
    // the thing this step asked for.
    if (state == AppLifecycleState.resumed) _checkAndAdvanceIfGranted();
  }

  Future<List<_WizardStep>> _buildSteps() async {
    final isAggressiveOem = await OemAutostartService.isAggressiveOem();
    final manufacturer = isAggressiveOem ? await OemAutostartService.detectManufacturer() : null;
    final oemInstruction = manufacturer != null ? findOemInstruction(manufacturer) : null;

    return [
      _WizardStep(
        icon: Icons.notifications_active_outlined,
        title: 'Notifications',
        description: 'So you get a welcome alert the moment you check in for the day.',
        skippable: true,
        actionLabel: 'Allow',
        isGranted: () async => (await FlutterForegroundTask.checkNotificationPermission()) == NotificationPermission.granted,
        request: () async => await FlutterForegroundTask.requestNotificationPermission(),
      ),
      _WizardStep(
        icon: Icons.my_location_rounded,
        title: 'Location — While Using the App',
        description: 'Confirms you\'re actually at an approved office location, not just on the right Wi-Fi network.',
        skippable: false,
        actionLabel: 'Allow',
        isGranted: () async => await Permission.locationWhenInUse.status.isGranted,
        request: () async => await Permission.locationWhenInUse.request(),
      ),
      _WizardStep(
        icon: Icons.location_on_rounded,
        title: 'Location — Allow All The Time',
        description: 'The important one: lets the app confirm your location even while it\'s closed, so check-in and check-out keep happening automatically. Pick "Allow all the time" on the next screen.',
        skippable: false,
        actionLabel: 'Allow',
        isGranted: () async => await Permission.locationAlways.status.isGranted,
        request: () async => await Permission.locationAlways.request(),
      ),
      _WizardStep(
        icon: Icons.battery_saver_outlined,
        title: 'Ignore Battery Optimization',
        description: 'Stops Android from shutting down the background attendance monitor to "save battery" — without this, arriving at the office may never trigger an automatic check-in at all.',
        skippable: false,
        actionLabel: 'Allow',
        isGranted: () async => await FlutterForegroundTask.isIgnoringBatteryOptimizations,
        request: () async => await FlutterForegroundTask.requestIgnoreBatteryOptimization(),
      ),
      if (oemInstruction != null)
        _WizardStep(
          icon: Icons.phonelink_setup_rounded,
          title: oemInstruction.brandLabel,
          description: '${oemInstruction.settingName} — ${oemInstruction.steps}',
          skippable: true,
          actionLabel: 'Open Settings',
          isGranted: OemAutostartService.isGuideMarkedShown,
          request: () async {
            await openOemSettings(oemInstruction);
            await OemAutostartService.markGuideShown();
          },
        ),
    ];
  }

  Future<void> _load() async {
    final steps = await _buildSteps();
    if (!mounted) return;

    // Skip straight to the first thing that still needs action instead of
    // making the user click through permissions they've already granted.
    var start = 0;
    for (; start < steps.length; start++) {
      if (!await steps[start].isGranted()) break;
    }

    if (start >= steps.length) {
      // Everything's already granted (e.g. re-shown only because it was
      // never marked complete before) — nothing to walk through.
      await _finish();
      return;
    }

    if (!mounted) return;
    setState(() {
      _steps = steps;
      _index = start;
    });
    await _refreshCurrentStatus();
  }

  Future<void> _refreshCurrentStatus() async {
    final steps = _steps;
    if (steps == null || _index >= steps.length) return;
    final granted = await steps[_index].isGranted();
    if (!mounted) return;
    setState(() => _currentGranted = granted);
  }

  /// Checks the current step and, if it's now granted, moves straight to the
  /// next one without waiting for a separate "Continue" tap — the whole point
  /// of walking through these one at a time is that granting/enabling each
  /// one is itself the signal to move on, not an extra confirmation step.
  Future<void> _checkAndAdvanceIfGranted() async {
    final steps = _steps;
    if (steps == null || _index >= steps.length) return;
    final granted = await steps[_index].isGranted();
    if (!mounted) return;
    if (granted) {
      _advance();
    } else {
      setState(() => _currentGranted = false);
    }
  }

  Future<void> _requestCurrent() async {
    final steps = _steps;
    if (steps == null) return;
    setState(() => _requesting = true);
    try {
      await steps[_index].request();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _requesting = false);
    await _checkAndAdvanceIfGranted();
  }

  void _advance() {
    final steps = _steps;
    if (steps == null) return;
    if (_index >= steps.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _currentGranted = null;
    });
    _refreshCurrentStatus();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    // Pop this route with our OWN context, not a parent's captured one — by
    // the time the user finishes the wizard, whatever ancestor originally
    // pushed this screen may have long since been disposed/rebuilt, which is
    // exactly what made this hang before (see main.dart's onDone).
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (steps == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final step = steps[_index];
    final granted = _currentGranted == true;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < steps.length; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _index ? AppColors.primary : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Step ${_index + 1} of ${steps.length}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
              const Spacer(),
              Icon(step.icon, size: 48, color: AppColors.primary),
              const SizedBox(height: 20),
              Text(step.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(step.description, style: TextStyle(color: Colors.grey.shade700, fontSize: 15, height: 1.4)),
              const SizedBox(height: 24),
              if (granted)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle_rounded, color: AppColors.success),
                      SizedBox(width: 10),
                      Expanded(child: Text('Allowed', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.success))),
                    ],
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _requesting ? null : (granted ? _advance : _requestCurrent),
                  child: _requesting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(granted ? (_index == steps.length - 1 ? 'Finish' : 'Continue') : step.actionLabel),
                ),
              ),
              if (!granted && step.skippable) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(onPressed: _advance, child: const Text('Skip for now')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
