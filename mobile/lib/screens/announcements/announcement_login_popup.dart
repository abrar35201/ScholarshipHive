import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

/// Shows announcements after employee login. The existing Announcements screen
/// remains unchanged and keeps the full announcement history available.
/// Read acknowledgement here is LOCAL to this device and account, not synced.
class AnnouncementLoginPopup {
  static Future<void> showIfNeeded(BuildContext context) async {
    if (!context.mounted) return;
    final provider = context.read<AppProvider>();
    final user = provider.currentUser;
    if (user == null) return;

    try {
      final items = await provider.api.getList('${ApiConfig.baseUrl}/announcements');
      // A private shift notification is delivered only to the authenticated user.
      List<dynamic> userNotices = [];
      try { userNotices = await provider.api.getList('${ApiConfig.baseUrl}/user-notices'); }
      catch (_) { /* Old backends may not have this endpoint yet. */ }
      if (!context.mounted || provider.currentUser?.id != user.id) return;
      if (items.isEmpty && userNotices.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final prefKey = 'announcement_popup_seen_v1_${user.id}';
      final seen = prefs.getStringList(prefKey)?.toSet() ?? <String>{};
      final unseen = <Map<String, dynamic>>[];
      final revisions = <String>[];

      for (final raw in items) {
        if (raw is! Map) continue;
        final a = Map<String, dynamic>.from(raw);
        if (a['id'] == null) continue;
        // New revisions are shown again following an edit.
        final revision = '${a['id']}:${a['updatedAt'] ?? a['createdAt'] ?? ''}';
        if (seen.contains(revision)) continue;
        unseen.add(a);
        revisions.add(revision);
      }
      for (final raw in userNotices) {
        if (raw is! Map) continue;
        final n = Map<String, dynamic>.from(raw);
        if (n['id'] == null) continue;
        final key = 'personal:${n['id']}';
        if (seen.contains(key)) continue;
        unseen.add({
          'title': n['title'] ?? 'Shift update',
          'body': n['body'] ?? '',
          'author': n['actorName'] ?? 'Management',
          'authorRole': 'Shift assignment',
        });
        revisions.add(key);
      }
      if (unseen.isEmpty || !context.mounted || provider.currentUser?.id != user.id) return;

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
                      Text('${a['author'] ?? 'Management'} (${a['authorRole'] ?? 'Unknown role'})',
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
        final latest = prefs.getStringList(prefKey)?.toSet() ?? <String>{};
        await prefs.setStringList(prefKey, {...latest, ...revisions}.toList());
      }
    } catch (e) {
      // Login should never fail because the notices endpoint is offline.
      debugPrint('Announcement login popup unavailable: $e');
    }
  }
}
