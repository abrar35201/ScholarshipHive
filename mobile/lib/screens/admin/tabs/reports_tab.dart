import 'dart:async';

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/business_day.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../models/admin_models.dart';
import '../../../models/report.dart';
import '../../../providers/app_provider.dart';
import '../../../services/file_opener_service.dart';
import '../widgets/report_card.dart';
import 'audit_reports_tab.dart';

const List<String> _departments = ['Calling', 'Processing', 'Others', 'Interns'];

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> with SingleTickerProviderStateMixin, RealtimeRefreshMixin {
  // Fallback only — live pushes (see RealtimeRefreshMixin) cover the normal case;
  // this just guards against a missed/dropped push.
  static const _autoRefreshInterval = Duration(seconds: 60);

  late final TabController _tabController;
  List<AdminReport>? _reports;
  String? _error;
  int? _openingFileId;
  Timer? _autoRefreshTimer;
  // Always starts on today — the control shouldn't remember a stale selection.
  DateTime _fromDate = businessToday();
  DateTime _toDate = businessToday();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _departments.length + 1, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _load();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) => _load());
    startListeningForRealtimeChanges();
  }

  @override
  void onRealtimeChanged() => _load();

  @override
  void dispose() {
    _tabController.dispose();
    _autoRefreshTimer?.cancel();
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().adminApiService.reports(fromDate: _fromDate, toDate: _toDate);
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

  Future<void> _refresh() => _load();

  bool get _isToday {
    final now = businessToday();
    bool isSameDay(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
    return isSameDay(_fromDate) && isSameDay(_toDate);
  }

  bool get _isRange =>
      _fromDate.year != _toDate.year || _fromDate.month != _toDate.month || _fromDate.day != _toDate.day;

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2020),
      lastDate: businessToday(),
    );
    if (picked == null) return;
    setState(() {
      _fromDate = picked;
      if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
    });
    _load();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: _fromDate,
      lastDate: businessToday(),
    );
    if (picked == null) return;
    setState(() => _toDate = picked);
    _load();
  }

  void _resetToToday() {
    setState(() {
      _fromDate = businessToday();
      _toDate = businessToday();
    });
    _load();
  }

  Future<void> _signOff(AdminReport r) async {
    await context.read<AppProvider>().adminApiService.signOffReport(r.id);
    await _load();
  }

  Future<void> _flag(AdminReport r) async {
    await context.read<AppProvider>().adminApiService.flagReport(r.id);
    await _load();
  }

  Future<void> _askForDetail(AdminReport r) async {
    await context.read<AppProvider>().adminApiService.askForDetailReport(r.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification sent to the employee.'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _openFile(ReportFileRef f) async {
    setState(() => _openingFileId = f.id);
    try {
      final bytes = await context.read<AppProvider>().adminApiService.downloadReportFile(f.id);
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

  Widget _buildDepartmentList(String department) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Builder(
        builder: (context) {
          final reports = _reports;
          if (reports == null) {
            if (_error != null) {
              return ListView(children: [const SizedBox(height: 100), Center(child: Text('Error: $_error'))]);
            }
            return const Center(child: CircularProgressIndicator());
          }
          final filtered = reports.where((r) => r.department == department).toList();
          if (filtered.isEmpty) {
            return ListView(children: const [SizedBox(height: 100), Center(child: Text('No reports for this date.'))]);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (context, i) => ReportCard(
              report: filtered[i],
              showDate: _isRange,
              openingFileId: _openingFileId,
              onOpenFile: _openFile,
              onSignOff: () => _signOff(filtered[i]),
              onFlag: () => _flag(filtered[i]),
              onAskForDetail: () => _askForDetail(filtered[i]),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onAuditTab = _tabController.index == _departments.length;

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            for (final department in _departments) Tab(text: department),
            const Tab(text: 'Audit Reports'),
          ],
        ),
        if (!onAuditTab)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text('From ${DateFormat('yyyy-MM-dd').format(_fromDate)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickToDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text('To ${DateFormat('yyyy-MM-dd').format(_toDate)}'),
                  ),
                ),
                if (!_isToday) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: _resetToToday, child: const Text('Today')),
                ],
              ],
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final department in _departments) _buildDepartmentList(department),
              const AuditReportsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

