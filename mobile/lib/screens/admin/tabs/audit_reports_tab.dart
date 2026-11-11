import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../models/audit_report.dart';
import '../../../models/report.dart';
import '../../../providers/app_provider.dart';
import '../../../services/file_opener_service.dart';
import '../audit_report_submit_screen.dart';

class AuditReportsTab extends StatefulWidget {
  const AuditReportsTab({super.key});

  @override
  State<AuditReportsTab> createState() => _AuditReportsTabState();
}

class _AuditReportsTabState extends State<AuditReportsTab> with RealtimeRefreshMixin {
  List<AuditReport>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    startListeningForRealtimeChanges();
  }

  @override
  void onRealtimeChanged() => _load();

  @override
  void dispose() {
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().auditReportService.list();
      if (!mounted) return;
      setState(() {
        _reports = result;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _openSubmitScreen() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AuditReportSubmitScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAuditor = context.watch<AppProvider>().currentUser?.role == 'Auditor';

    return Scaffold(
      floatingActionButton: isAuditor
          ? FloatingActionButton.extended(
              onPressed: _openSubmitScreen,
              icon: const Icon(Icons.add),
              label: const Text('New Audit Report'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            final reports = _reports;
            if (reports == null) {
              if (_error != null) {
                return ListView(children: [const SizedBox(height: 100), Center(child: Text('Error: $_error'))]);
              }
              return const Center(child: CircularProgressIndicator());
            }
            if (reports.isEmpty) {
              return ListView(children: const [SizedBox(height: 100), Center(child: Text('No audit reports uploaded yet.'))]);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (context, i) => _AuditReportCard(report: reports[i]),
            );
          },
        ),
      ),
    );
  }
}

class _AuditReportCard extends StatefulWidget {
  final AuditReport report;
  const _AuditReportCard({required this.report});

  @override
  State<_AuditReportCard> createState() => _AuditReportCardState();
}

class _AuditReportCardState extends State<_AuditReportCard> {
  bool _expanded = false;
  int? _openingFileId;

  Future<void> _openFile(ReportFileRef f) async {
    setState(() => _openingFileId = f.id);
    try {
      final bytes = await context.read<AppProvider>().auditReportService.downloadFile(f.id);
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
    final initials = r.auditorUsername.isNotEmpty ? r.auditorUsername.substring(0, r.auditorUsername.length >= 2 ? 2 : 1).toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(
                          'By ${r.auditorUsername} · ${DateFormat('yyyy-MM-dd hh:mm a').format(r.createdAt.toLocal())}',
                          style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.inkMuted),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    r.textContent?.isNotEmpty == true ? r.textContent! : 'No text entered.',
                    style: const TextStyle(fontSize: 13.5, height: 1.5),
                  ),
                ),
                if (r.files.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final f in r.files)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_file_rounded, size: 18, color: AppColors.primaryDark),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f.fileName, overflow: TextOverflow.ellipsis)),
                          _openingFileId == f.id
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                  onPressed: () => _openFile(f),
                                ),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
