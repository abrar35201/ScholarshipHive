$ErrorActionPreference = 'Stop'

# Run this inside the extracted ScholarshipHive project (or any parent folder).
$main = Get-ChildItem -Path (Get-Location) -Filter 'main.dart' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]mobile[\\/]lib[\\/]main\.dart$' } |
    Select-Object -First 1
if (-not $main) { throw 'mobile\lib\main.dart nahi mila. Script extracted project ke main folder se chalao.' }

$mobileLib = Split-Path $main.FullName -Parent
$screenDir = Join-Path $mobileLib 'screens\announcements'
$popupFile = Join-Path $screenDir 'announcement_login_popup.dart'
if (-not (Test-Path $screenDir)) { throw "Announcements screen folder nahi mila: $screenDir" }

$source = [IO.File]::ReadAllText($main.FullName)
$import = "import 'screens/announcements/announcement_login_popup.dart';"
$oldInit = '    _checkPermissionOnboarding();'
$newInit = @'
    _checkPermissionOnboarding().then((_) async {
      // Wait for any first-login guidance/notice before presenting announcements.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) await AnnouncementLoginPopup.showIfNeeded(context);
    });
'@.TrimEnd()

if (-not $source.Contains('AnnouncementLoginPopup.showIfNeeded(context)')) {
    if (-not $source.Contains($oldInit)) { throw 'main.dart initState ka expected code nahi mila; koi change nahi ki.' }
    Copy-Item $main.FullName "$($main.FullName).before_announcement_popup.bak" -Force
    if (-not $source.Contains($import)) {
        $anchor = "import 'screens/admin/admin_home_screen.dart';"
        if (-not $source.Contains($anchor)) { throw 'main.dart imports differ; manual check required.' }
        $source = $source.Replace($anchor, "$anchor`n$import")
    }
    $source = $source.Replace($oldInit, $newInit)
    [IO.File]::WriteAllText($main.FullName, $source, [Text.UTF8Encoding]::new($false))
}

$dart = @'
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

/// Displays announcements after employee login, without altering the existing
/// Announcements page. Acknowledgements are stored per user on this device.
class AnnouncementLoginPopup {
  static Future<void> showIfNeeded(BuildContext context) async {
    if (!context.mounted) return;
    final provider = context.read<AppProvider>();
    final user = provider.currentUser;
    if (user == null || user.role != 'Employee') return;

    try {
      final items = await provider.api.getList('${ApiConfig.baseUrl}/announcements');
      if (!context.mounted || items.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final prefKey = 'announcement_popup_seen_v1_${user.id}';
      final alreadySeen = prefs.getStringList(prefKey)?.toSet() ?? <String>{};
      final unseen = <Map<String, dynamic>>[];
      final revisions = <String>[];

      for (final raw in items) {
        if (raw is! Map) continue;
        final a = Map<String, dynamic>.from(raw);
        if (a['id'] == null) continue;
        // Edits make the announcement eligible to pop up again.
        final revision = '${a['id']}:${a['updatedAt'] ?? a['createdAt'] ?? ''}';
        if (alreadySeen.contains(revision)) continue;
        unseen.add(a);
        revisions.add(revision);
      }
      if (unseen.isEmpty || !context.mounted) return;

      final acknowledged = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.campaign, color: Colors.deepOrange),
            SizedBox(width: 10),
            Expanded(child: Text('Important announcements')),
          ]),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 390),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: unseen.length,
                separatorBuilder: (_, __) => const Divider(height: 24),
                itemBuilder: (_, index) {
                  final a = unseen[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${a['title'] ?? 'Announcement'}',
                          style: Theme.of(dialogContext).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text('${a['body'] ?? ''}'),
                      const SizedBox(height: 5),
                      Text('${a['author'] ?? 'Management'}',
                          style: Theme.of(dialogContext).textTheme.bodySmall),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text("I've read these"),
            ),
          ],
        ),
      );
      if (acknowledged == true) {
        // Merge rather than overwrite previously seen announcements.
        final latest = prefs.getStringList(prefKey)?.toSet() ?? <String>{};
        await prefs.setStringList(prefKey, {...latest, ...revisions}.toList());
      }
    } catch (e) {
      // Never block normal login because of a temporary announcement API issue.
      debugPrint('Announcement login popup unavailable: $e');
    }
  }
}
'@

if (Test-Path $popupFile) {
    Copy-Item $popupFile "$popupFile.bak" -Force
}
[IO.File]::WriteAllText($popupFile, $dart, [Text.UTF8Encoding]::new($false))

Write-Host "Announcement popup added!" -ForegroundColor Green
Write-Host "main.dart: $($main.FullName)"
Write-Host "popup:     $popupFile"
Write-Host "Existing Announcements page unchanged. Restart Flutter with capital R." -ForegroundColor Cyan
