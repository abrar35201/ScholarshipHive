import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/attendance_cycles.dart';
import '../../core/business_day.dart';
import '../../providers/app_provider.dart';

/// One user's full check-in/check-out log across a date range — reached by
/// tapping a row in the Attendance tab's day roster (opens on just that one
/// day by default), with From/To pickers right here to widen it to however
/// far back the admin actually needs — a full month, a custom window,
/// whatever — without a separate screen for that.
class UserDayAttendanceScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final DateTime date;

  const UserDayAttendanceScreen({super.key, required this.userId, required this.userName, required this.date});

  @override
  State<UserDayAttendanceScreen> createState() => _UserDayAttendanceScreenState();
}

class _UserDayAttendanceScreenState extends State<UserDayAttendanceScreen> {
  late Future<Map<DateTime, List<CheckCycle>>> _future;
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    _fromDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
    _toDate = _fromDate;
    _load();
  }

  void _load() {
    _future = context.read<AppProvider>().adminApiService.userDetail(widget.userId).then((detail) => groupHistoryByDay(detail.history));
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(context: context, initialDate: _fromDate, firstDate: DateTime(2020), lastDate: businessToday());
    if (picked == null) return;
    setState(() {
      _fromDate = picked;
      if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
    });
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(context: context, initialDate: _toDate, firstDate: _fromDate, lastDate: businessToday());
    if (picked == null) return;
    setState(() => _toDate = picked);
  }

  bool _inRange(DateTime day) => !day.isBefore(_fromDate) && !day.isAfter(_toDate);

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy');
    final dayHeaderFmt = DateFormat('EEEE, d MMM yyyy');
    final timeFmt = DateFormat('hh:mm:ss a');

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
              onRefresh: _refresh,
              child: FutureBuilder<Map<DateTime, List<CheckCycle>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(children: [const SizedBox(height: 100), Center(child: Text('Error: ${snapshot.error}'))]);
                  }

                  final byDay = snapshot.data!;
                  final days = byDay.keys.where(_inRange).toList()..sort((a, b) => b.compareTo(a));

                  if (days.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 100),
                        Center(child: Text('No check-ins or check-outs in this range.', style: TextStyle(color: AppColors.inkMuted))),
                      ],
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: days.length,
                    itemBuilder: (context, dayIndex) {
                      final day = days[dayIndex];
                      final cycles = byDay[day]!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (dayIndex > 0) const Padding(padding: EdgeInsets.only(bottom: 16), child: Divider(height: 1, thickness: 1.4, color: AppColors.ink)),
                            Text(dayHeaderFmt.format(day), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                            const SizedBox(height: 8),
                            for (final c in cycles)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primarySoft)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.login_rounded, color: AppColors.success, size: 18),
                                    const SizedBox(width: 6),
                                    Text(c.checkIn != null ? timeFmt.format(c.checkIn!.timestamp.toLocal()) : '—', style: const TextStyle(fontSize: 12.5)),
                                    const SizedBox(width: 14),
                                    const Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      c.checkOut != null ? timeFmt.format(c.checkOut!.timestamp.toLocal()) : 'Still checked in',
                                      style: TextStyle(fontSize: 12.5, color: c.checkOut == null ? AppColors.success : null),
                                    ),
                                    const Spacer(),
                                    if ((c.checkOut ?? c.checkIn)?.routerName != null)
                                      Flexible(
                                        child: Text(
                                          (c.checkOut ?? c.checkIn)!.routerName!,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
