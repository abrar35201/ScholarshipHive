import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/report.dart';
import '../../providers/app_provider.dart';
import '../../services/file_opener_service.dart';

/// Read-only view of one of the employee's own past reports — editing only
/// ever happens on the day it's for, via ReportScreen. Deliberately doesn't
/// show check-in/check-out timings (Admin/Auditor-only, see AttendanceController).
class ReportDetailScreen extends StatefulWidget {
  final DailyReport report;
  final bool isTextReport;

  const ReportDetailScreen({super.key, required this.report, required this.isTextReport});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  int? _openingFileId;

  Future<void> _openFile(ReportFileRef f) async {
    setState(() => _openingFileId = f.id);
    try {
      final bytes = await context.read<AppProvider>().reportService.downloadMyReportFile(f.id);
      await FileOpenerService.openBytes(bytes, f.fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _openingFileId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Scaffold(
      appBar: AppBar(title: Text(r.date)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)),
                  alignment: Alignment.center,
                  child: Icon(widget.isTextReport ? Icons.article_outlined : Icons.bar_chart_rounded, size: 18, color: AppColors.primaryDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r.date, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: r.isEditable ? AppColors.success.withValues(alpha: 0.12) : AppColors.inkMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    r.isEditable ? 'Still editable' : 'Locked',
                    style: TextStyle(color: r.isEditable ? AppColors.success : AppColors.inkMuted, fontWeight: FontWeight.w700, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (widget.isTextReport)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  r.textContent?.isNotEmpty == true ? r.textContent! : 'No text entered.',
                  style: const TextStyle(fontSize: 14, height: 1.55),
                ),
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _MiniStat(label: 'Unread chats', value: r.unreadChats),
                  _MiniStat(label: 'New leads', value: r.newLeads),
                  _MiniStat(label: 'Qualified', value: r.qualifiedLeads),
                  _MiniStat(label: 'Follow up', value: r.followUp),
                  _MiniStat(label: 'Calls', value: r.calls),
                  _MiniStat(label: 'Potential', value: r.potential),
                  _MiniStat(label: "Walk-in's", value: r.walkIns),
                  _MiniStat(label: 'Conversion', value: r.conversion),
                ],
              ),
            const SizedBox(height: 24),
            Text('Attachments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (r.files.isEmpty)
              Text('No files attached.', style: TextStyle(color: AppColors.inkMuted))
            else
              for (final f in r.files)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primarySoft),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(f.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                      _openingFileId == f.id
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: const Icon(Icons.open_in_new_rounded, size: 20),
                              onPressed: () => _openFile(f),
                              tooltip: 'Open',
                            ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19, color: AppColors.primaryDark)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}
