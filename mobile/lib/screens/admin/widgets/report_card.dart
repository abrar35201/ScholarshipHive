import 'package:flutter/material.dart';
import '../../../core/app_theme.dart';
import '../../../models/admin_models.dart';
import '../../../models/report.dart';

/// A single report shown as a self-contained card with every field visible at
/// once — the mobile equivalent of the web admin panel's wide data table,
/// without needing to scroll sideways to see the rest of a row.
class ReportCard extends StatelessWidget {
  final AdminReport report;
  final bool showDate;
  final int? openingFileId;
  final void Function(ReportFileRef) onOpenFile;
  final VoidCallback? onSignOff;
  final VoidCallback? onFlag;
  final VoidCallback? onAskForDetail;

  const ReportCard({
    super.key,
    required this.report,
    this.showDate = true,
    required this.openingFileId,
    required this.onOpenFile,
    this.onSignOff,
    this.onFlag,
    this.onAskForDetail,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    final isTextDepartment = r.department != 'Calling';
    final initials = r.username.isNotEmpty ? r.username.substring(0, r.username.length >= 2 ? 2 : 1).toUpperCase() : '?';
    final (tagBg, tagFg, tagLabel) = switch (r.reviewStatus) {
      'SignedOff' => (AppColors.success.withValues(alpha: 0.12), AppColors.success, 'Signed off'),
      'Flagged' => (AppColors.danger.withValues(alpha: 0.1), AppColors.danger, 'Flagged'),
      'NeedsMoreDetail' => (AppColors.warning.withValues(alpha: 0.12), AppColors.warning, 'Needs detail'),
      _ => (AppColors.primarySoft, AppColors.primaryDark, 'New'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.primaryDark)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(r.username, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              if (showDate) Padding(padding: const EdgeInsets.only(right: 8), child: Text(r.date, style: TextStyle(color: AppColors.inkMuted, fontSize: 12))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(99)),
                child: Text(tagLabel, style: TextStyle(color: tagFg, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isTextDepartment)
            Text(
              r.textContent?.isNotEmpty == true ? r.textContent! : '(no text entered)',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MetricChip('Unread Chats', r.unreadChats),
                MetricChip('New Leads', r.newLeads),
                MetricChip('Qualified', r.qualifiedLeads),
                MetricChip('Follow Up', r.followUp),
                MetricChip('Calls', r.calls),
                MetricChip('Potential', r.potential),
                MetricChip("Walk-in's", r.walkIns),
                MetricChip('Conversion', r.conversion),
              ],
            ),
          if (r.files.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in r.files)
                  InkWell(
                    onTap: openingFileId == f.id ? null : () => onOpenFile(f),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          openingFileId == f.id
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.attach_file_rounded, size: 14, color: AppColors.primaryDark),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(f.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (onSignOff != null || onFlag != null || onAskForDetail != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onSignOff != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSignOff,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: AppColors.success, side: BorderSide(color: AppColors.success.withValues(alpha: 0.3))),
                      child: const Text('Sign off', style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                if (onAskForDetail != null) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onAskForDetail,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                      child: const Text('Ask for detail', style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ],
                if (onFlag != null) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onFlag,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: AppColors.danger, side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3))),
                      child: const Text('Flag', style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MetricChip extends StatelessWidget {
  final String label;
  final int value;
  const MetricChip(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          Text('$value', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        ],
      ),
    );
  }
}
