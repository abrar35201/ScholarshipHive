import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/business_day.dart';
import '../../models/attendance_day.dart';
import '../../providers/app_provider.dart';

/// An employee's own attendance for the last month — Present/Absent only.
/// Exact check-in/check-out times are an Admin/Auditor-only view. Shown as a
/// calendar (mirroring the admin web panel's per-user attendance calendar),
/// with the plain day-by-day list underneath for anything the grid can't
/// show at a glance.
class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key});

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  List<AttendanceDay>? _days;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().attendanceService.mine();
      if (!mounted) return;
      setState(() {
        _days = result;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load attendance: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: Builder(
            builder: (context) {
              final days = _days;
              if (days == null) {
                if (_error != null) {
                  return ListView(children: [const SizedBox(height: 100), Center(child: Text(_error!))]);
                }
                return const Center(child: CircularProgressIndicator());
              }

              final byDate = <DateTime, String>{
                for (final d in days) DateUtils.dateOnly(DateTime.parse(d.date)): d.status,
              };
              final months = byDate.keys.map((d) => DateTime(d.year, d.month)).toSet().toList()
                ..sort((a, b) => b.compareTo(a));
              final presentCount = days.where((d) => d.present).length;

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$presentCount of ${days.length}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('days present, all time', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                            ],
                          ),
                        ),
                        Icon(Icons.event_available_rounded, color: Colors.white.withValues(alpha: 0.85), size: 30),
                      ],
                    ),
                  ),
                  for (final month in months) ...[
                    const SizedBox(height: 20),
                    _MonthCalendar(month: month, byDate: byDate),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final Map<DateTime, String> byDate;

  const _MonthCalendar({required this.month, required this.byDate});

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mon..7=Sun
    final leading = firstWeekday - 1;
    final today = businessToday();

    // This month's own actual counts — computed only from days that
    // actually fall within THIS calendar month, so a date range spanning two
    // months (e.g. "last month to today") shows each month's totals
    // separately instead of one combined figure under both.
    var presentCount = 0, lateCount = 0, absentCount = 0, extraCount = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      if (date.isAfter(today)) continue;
      switch (byDate[date]) {
        case 'Present':
          presentCount++;
        case 'Late':
          lateCount++;
        case 'Absent':
          absentCount++;
        case 'Extra':
          extraCount++;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map((d) => Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted)))))
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5),
            itemCount: leading + daysInMonth,
            itemBuilder: (context, i) {
              if (i < leading) return const SizedBox();
              final day = i - leading + 1;
              final date = DateTime(month.year, month.month, day);
              final isFuture = date.isAfter(today);
              final status = byDate[date];

              Color bg;
              Color fg;
              switch (status) {
                case 'Present':
                  bg = AppColors.success.withValues(alpha: 0.12);
                  fg = AppColors.success;
                case 'Late':
                  bg = AppColors.warning.withValues(alpha: 0.12);
                  fg = AppColors.warning;
                case 'Absent':
                  bg = AppColors.danger.withValues(alpha: 0.1);
                  fg = AppColors.danger;
                case 'Extra':
                  // A weekend day off, but they still came in and checked in
                  // anyway — working extra, not just "present" on an
                  // ordinary working day, so it gets its own color rather
                  // than blending into the same green as a normal arrival.
                  bg = AppColors.alt.withValues(alpha: 0.12);
                  fg = AppColors.alt;
                default:
                  // 'Weekend' with no attendance, a future date, or no data yet.
                  bg = AppColors.surfaceLight;
                  fg = AppColors.inkMuted;
              }
              if (isFuture) {
                bg = AppColors.surfaceLight;
                fg = AppColors.inkMuted;
              }

              return Container(
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: Text('$day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MonthCountStat(color: AppColors.success, label: 'Present', count: presentCount),
              _MonthCountStat(color: AppColors.warning, label: 'Late', count: lateCount),
              _MonthCountStat(color: AppColors.danger, label: 'Absent', count: absentCount),
              if (extraCount > 0) _MonthCountStat(color: AppColors.alt, label: 'Extra', count: extraCount),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Legend(color: AppColors.success, label: 'Present'),
              _Legend(color: AppColors.warning, label: 'Late'),
              _Legend(color: AppColors.danger, label: 'Absent'),
              _Legend(color: AppColors.alt, label: 'Extra time (weekend)'),
              _Legend(color: AppColors.inkMuted, label: 'Weekend / n.a.'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthCountStat extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _MonthCountStat({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 5), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              Text('$count', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
      ],
    );
  }
}
