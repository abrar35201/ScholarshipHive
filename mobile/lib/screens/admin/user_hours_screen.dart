import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/business_day.dart';
import '../../models/admin_models.dart';
import '../../providers/app_provider.dart';

/// One person's day-by-day accumulated presence — reached by tapping their
/// row in the Hours tab. Defaults to whatever range that list was showing,
/// but can be overridden here just for this person without disturbing the
/// list's own global range.
class UserHoursScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final DateTime defaultFromDate;
  final DateTime defaultToDate;

  const UserHoursScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.defaultFromDate,
    required this.defaultToDate,
  });

  @override
  State<UserHoursScreen> createState() => _UserHoursScreenState();
}

class _UserHoursScreenState extends State<UserHoursScreen> {
  HoursDetail? _detail;
  String? _error;
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    _fromDate = widget.defaultFromDate;
    _toDate = widget.defaultToDate;
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().adminApiService.hoursDetail(widget.userId, from: _fromDate, to: _toDate);
      if (!mounted) return;
      setState(() {
        _detail = result;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load hours: $e');
    }
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(context: context, initialDate: _fromDate, firstDate: DateTime(2020), lastDate: businessToday());
    if (picked == null) return;
    setState(() {
      _fromDate = picked;
      if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
    });
    _load();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(context: context, initialDate: _toDate, firstDate: _fromDate, lastDate: businessToday());
    if (picked == null) return;
    setState(() => _toDate = picked);
    _load();
  }

  String _fmt(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    final dayFmt = DateFormat('EEEE, d MMM yyyy');

    return Scaffold(
      appBar: AppBar(title: Text(widget.userName)),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.primarySoft))),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text('From ${dateFmt.format(_fromDate)}', style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickToDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text('To ${dateFmt.format(_toDate)}', style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: Builder(
                builder: (context) {
                  final detail = _detail;
                  if (detail == null) {
                    if (_error != null) {
                      return ListView(children: [const SizedBox(height: 100), Center(child: Text(_error!))]);
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(18)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_fmt(detail.totalMinutes), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text('Worked, ${detail.days.length} days', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                                  const SizedBox(height: 4),
                                  Text('Gap Time: ${_fmt(detail.totalGapMinutes)}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Icon(Icons.access_time_rounded, color: Colors.white.withValues(alpha: 0.85), size: 30),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final d in detail.days)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primarySoft)),
                          child: Row(
                            children: [
                              Expanded(child: Text(dayFmt.format(d.date), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Worked: ${_fmt(d.minutes)}${d.stillOpen ? ' (ongoing)' : ''}',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: d.minutes > 0 ? AppColors.success : AppColors.inkMuted)),
                                  Text('Gap: ${_fmt(d.gapMinutes)}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (detail.days.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Center(child: Text('No presence recorded in this range.', style: TextStyle(color: AppColors.inkMuted))),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
