import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/report.dart';
import '../../providers/app_provider.dart';
import 'report_detail_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  List<DailyReport>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().reportService.myReports();
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

  void _openDetail(DailyReport r, bool isTextReport) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReportDetailScreen(report: r, isTextReport: isTextReport)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTextReport = context.watch<AppProvider>().currentUser?.department != 'Calling';

    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: SafeArea(
        child: RefreshIndicator(
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
                return ListView(children: const [SizedBox(height: 100), Center(child: Text('No reports yet.'))]);
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = reports[i];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openDetail(r, isTextReport),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primarySoft),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)),
                              alignment: Alignment.center,
                              child: Icon(
                                isTextReport ? Icons.article_outlined : Icons.bar_chart_rounded,
                                size: 18,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.date, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                  const SizedBox(height: 3),
                                  Text(
                                    isTextReport
                                        ? (r.textContent?.isNotEmpty == true ? r.textContent! : '(no text entered)')
                                        : 'Leads ${r.newLeads} · Conversion ${r.conversion}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: r.isEditable ? AppColors.success.withValues(alpha: 0.12) : AppColors.inkMuted.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                r.isEditable ? 'Editable' : 'Locked',
                                style: TextStyle(
                                  color: r.isEditable ? AppColors.success : AppColors.inkMuted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
