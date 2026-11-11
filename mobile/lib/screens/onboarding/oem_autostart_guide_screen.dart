import 'package:android_intent_plus/android_intent.dart';
import 'package:app_settings/app_settings.dart';

/// One specific phone-settings screen to try opening for a given brand, with
/// a fallback if the primary attempt isn't available on this exact device/OS
/// version. [action]/[componentPackage]+[componentClass] map straight to an
/// Android Intent; leave both null to go straight to the universal fallback
/// (the app's own "App Info" settings page, which always exists).
class OemIntentAttempt {
  final String? action;
  final String? componentPackage;
  final String? componentClass;
  const OemIntentAttempt({this.action, this.componentPackage, this.componentClass});
}

class OemInstruction {
  /// Matches if the device's lowercased manufacturer string CONTAINS this.
  final String matches;
  final String brandLabel;
  final String settingName;
  final String steps;
  final List<OemIntentAttempt> attempts;

  const OemInstruction({
    required this.matches,
    required this.brandLabel,
    required this.settingName,
    required this.steps,
    this.attempts = const [],
  });
}

/// Per-brand instructions and best-known Intents for reaching that phone's
/// own extra autostart/background-app-management screen. Where a brand has
/// no [attempts] listed, the guide still explains what to look for and opens
/// the general App Info screen as a starting point.
const List<OemInstruction> oemInstructions = [
  OemInstruction(
    matches: 'xiaomi',
    brandLabel: 'Xiaomi / Redmi / POCO (MIUI)',
    settingName: 'Autostart',
    steps: 'Turn ON "Autostart" for ScholarshipHive, then also check Battery Saver is set to "No restrictions" for this app.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.miui.securitycenter', componentClass: 'com.miui.permcenter.autostart.AutoStartManagementActivity'),
      OemIntentAttempt(componentPackage: 'com.miui.securitycenter', componentClass: 'com.miui.powercenter.PowerSettings'),
    ],
  ),
  OemInstruction(
    matches: 'vivo',
    brandLabel: 'Vivo / iQOO (Funtouch OS / OriginOS)',
    settingName: 'Autostart / Background power consumption',
    steps: 'Turn ON "Autostart" for ScholarshipHive, and allow "Background power consumption" under i Manager > App manager.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.vivo.permissionmanager', componentClass: 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity'),
      OemIntentAttempt(componentPackage: 'com.iqoo.secure', componentClass: 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity'),
      OemIntentAttempt(componentPackage: 'com.iqoo.secure', componentClass: 'com.iqoo.secure.ui.phoneoptimize.BgStartUpManager'),
      OemIntentAttempt(componentPackage: 'com.vivo.abe', componentClass: 'com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity'),
    ],
  ),
  OemInstruction(
    matches: 'iqoo',
    brandLabel: 'iQOO (OriginOS)',
    settingName: 'Autostart / Background power consumption',
    steps: 'Turn ON "Autostart" for ScholarshipHive, and allow "Background power consumption" under i Manager > App manager.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.vivo.permissionmanager', componentClass: 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity'),
      OemIntentAttempt(componentPackage: 'com.iqoo.secure', componentClass: 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity'),
      OemIntentAttempt(componentPackage: 'com.iqoo.secure', componentClass: 'com.iqoo.secure.ui.phoneoptimize.BgStartUpManager'),
    ],
  ),
  OemInstruction(
    matches: 'oppo',
    brandLabel: 'Oppo (ColorOS)',
    settingName: 'Startup Manager / Allow background running',
    steps: 'Allow ScholarshipHive to start automatically and run in the background under Settings > Battery > App Battery Management.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.coloros.safecenter', componentClass: 'com.coloros.safecenter.permission.startup.StartupAppListActivity'),
      OemIntentAttempt(componentPackage: 'com.coloros.safecenter', componentClass: 'com.coloros.safecenter.startupapp.StartupAppListActivity'),
      OemIntentAttempt(componentPackage: 'com.oppo.safe', componentClass: 'com.oppo.safe.permission.startup.StartupAppListActivity'),
    ],
  ),
  OemInstruction(
    matches: 'realme',
    brandLabel: 'Realme (Realme UI)',
    settingName: 'Startup Manager / Allow background running',
    steps: 'Allow ScholarshipHive to start automatically and run in the background under Settings > Battery > App Battery Management.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.coloros.safecenter', componentClass: 'com.coloros.safecenter.startupapp.StartupAppListActivity'),
      OemIntentAttempt(componentPackage: 'com.oppo.safe', componentClass: 'com.oppo.safe.permission.startup.StartupAppListActivity'),
    ],
  ),
  OemInstruction(
    matches: 'huawei',
    brandLabel: 'Huawei (EMUI / HarmonyOS)',
    settingName: 'App launch',
    steps: 'Under Settings > Battery > App launch, find ScholarshipHive, turn OFF "Manage automatically", then turn ON Auto-launch, Secondary launch, and Run in background.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.huawei.systemmanager', componentClass: 'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity'),
      OemIntentAttempt(componentPackage: 'com.huawei.systemmanager', componentClass: 'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity'),
      OemIntentAttempt(componentPackage: 'com.huawei.systemmanager', componentClass: 'com.huawei.systemmanager.optimize.process.ProtectActivity'),
    ],
  ),
  OemInstruction(
    matches: 'honor',
    brandLabel: 'Honor (Magic UI)',
    settingName: 'App launch',
    steps: 'Under Settings > Battery > App launch, find ScholarshipHive, turn OFF "Manage automatically", then turn ON Auto-launch, Secondary launch, and Run in background.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.huawei.systemmanager', componentClass: 'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity'),
      OemIntentAttempt(componentPackage: 'com.huawei.systemmanager', componentClass: 'com.huawei.systemmanager.optimize.process.ProtectActivity'),
    ],
  ),
  OemInstruction(
    matches: 'asus',
    brandLabel: 'Asus (ZenUI)',
    settingName: 'Auto-start Manager',
    steps: 'Open Mobile Manager > Auto-start Manager and allow ScholarshipHive to start automatically.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.asus.mobilemanager', componentClass: 'com.asus.mobilemanager.autostart.AutoStartActivity'),
      OemIntentAttempt(componentPackage: 'com.asus.mobilemanager', componentClass: 'com.asus.mobilemanager.powersaver.PowerSaverSettings'),
      OemIntentAttempt(componentPackage: 'com.asus.mobilemanager', componentClass: 'com.asus.mobilemanager.entry.FunctionActivity'),
    ],
  ),
  OemInstruction(
    matches: 'samsung',
    brandLabel: 'Samsung (One UI)',
    settingName: 'Background usage limits',
    steps: 'Under Settings > Battery > Background usage limits, make sure ScholarshipHive is NOT in "Sleeping apps" or "Deep sleeping apps".',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.samsung.android.lool', componentClass: 'com.samsung.android.sm.ui.battery.BatteryActivity'),
      OemIntentAttempt(componentPackage: 'com.samsung.android.lool', componentClass: 'com.samsung.android.sm.battery.ui.BatteryActivity'),
      OemIntentAttempt(componentPackage: 'com.samsung.android.lool', componentClass: 'com.samsung.android.sm.battery.ui.usage.CheckableAppListActivity'),
      OemIntentAttempt(componentPackage: 'com.samsung.android.sm', componentClass: 'com.samsung.android.sm.ui.battery.BatteryActivity'),
      OemIntentAttempt(componentPackage: 'com.samsung.android.sm', componentClass: 'com.samsung.android.sm.battery.ui.BatteryActivity'),
    ],
  ),
  OemInstruction(
    matches: 'oneplus',
    brandLabel: 'OnePlus (OxygenOS)',
    settingName: 'Auto-launch / Battery optimization',
    steps: 'Under Settings > Battery, make sure ScholarshipHive is set to "Don\'t optimize" / unrestricted. OnePlus\'s own autostart screen is unreliable across models, so this general battery screen is the more dependable option here.',
    attempts: [
      OemIntentAttempt(componentPackage: 'com.oneplus.security', componentClass: 'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity'),
      OemIntentAttempt(action: 'com.android.settings.action.BACKGROUND_OPTIMIZE'),
    ],
  ),
  // Infinix (XOS), Tecno (HiOS), and itel all come from the same parent
  // company (Transsion) and share the same "Phone Manager" pattern as
  // Xiaomi/Vivo/Oppo — but no specific Activity names have been verified
  // for them yet, so these fall straight through to the universal App Info
  // fallback (see openOemSettings) rather than guessing at ones that might
  // not exist on a given model.
  OemInstruction(
    matches: 'infinix',
    brandLabel: 'Infinix (XOS)',
    settingName: 'Autostart / Background app management',
    steps: 'Open Phone Manager (or Settings > Apps > ScholarshipHive > Battery), turn ON "Autostart", and set battery usage to "Allow background activity".',
  ),
  OemInstruction(
    matches: 'tecno',
    brandLabel: 'Tecno (HiOS)',
    settingName: 'Autostart / Background app management',
    steps: 'Open Phone Manager (or Settings > Apps > ScholarshipHive > Battery), turn ON "Autostart", and set battery usage to "Allow background activity".',
  ),
  OemInstruction(
    matches: 'itel',
    brandLabel: 'itel',
    settingName: 'Autostart / Background app management',
    steps: 'Open Phone Manager (or Settings > Apps > ScholarshipHive > Battery), turn ON "Autostart", and set battery usage to "Allow background activity".',
  ),
];

OemInstruction? findOemInstruction(String manufacturer) {
  for (final i in oemInstructions) {
    if (manufacturer.contains(i.matches)) return i;
  }
  return null;
}

/// Tries each of [instruction]'s best-known Intents for reaching that brand's
/// own autostart/battery screen in order; if none work on this exact
/// device/OS version, falls back to the app's own "App Info" screen, which
/// always exists. Safe to call with a null instruction (goes straight to the
/// fallback) for brands with no specific attempts on file.
Future<void> openOemSettings(OemInstruction? instruction) async {
  if (instruction != null) {
    for (final attempt in instruction.attempts) {
      try {
        final intent = AndroidIntent(
          action: attempt.action ?? 'android.intent.action.MAIN',
          package: attempt.componentPackage,
          componentName: attempt.componentClass,
        );
        await intent.launch();
        return;
      } catch (_) {
        // Try the next known attempt for this brand.
      }
    }
  }

  try {
    await AppSettings.openAppSettings();
  } catch (_) {
    // Nothing more we can do — the on-screen instructions still tell the
    // user what to look for manually.
  }
}
