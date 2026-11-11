import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/business_day.dart';
import '../../../models/admin_models.dart';
import '../../../providers/app_provider.dart';
import '../user_hours_screen.dart';

/// Every active employee's total accumulated presence (see
/// AttendanceDurationService) over a selectable date range — defaults to the
/// last calendar month through today. Tapping a row drills into that
/// person's day-by-day breakdown.
class HoursTab extends StatefulWidget {
  const HoursTab({super.key});

  @override
  State<HoursTab> createState() => _HoursTabState();
}

class _HoursTabState extends State<HoursTab> {
  List<HoursListEntry>? _entries;
  String? _error;
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    final today = businessToday();
    _toDate = today;
    _fromDate = DateTime(today.year, today.month - 1, today.day);
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().adminApiService.hours(from: _fromDate, to: _toDate);
      if (!mounted) return;
      setState(() {
        _entries = result;
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                final entries = _entries;
                if (entries == null) {
                  if (_error != null) {
                    return ListView(children: [const SizedBox(height: 100), Center(child: Text(_error!))]);
                  }
                  return const Center(child: CircularProgressIndicator());
                }
                if (entries.isEmpty) {
                  return ListView(children: const [SizedBox(height: 100), Center(child: Text('No employees yet.'))]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final initials = e.name.isNotEmpty ? e.name.substring(0, e.name.length >= 2 ? 2 : 1).toUpperCase() : '?';
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => UserHoursScreen(userId: e.userId, userName: e.name, defaultFromDate: _fromDate, defaultToDate: _toDate),
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primarySoft)),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primarySoft,
                              child: Text(initials, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700, fontSize: 12.5)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                  Text(e.department, style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Worked: ${_fmt(e.totalMinutes)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primaryDark)),
                                Text('Gap: ${_fmt(e.gapMinutes)}', style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                              ],
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
