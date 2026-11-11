import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/business_day.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../models/admin_models.dart';
import '../../../providers/app_provider.dart';
import '../user_day_attendance_screen.dart';

const List<String> _departments = ['Calling', 'Processing', 'Others', 'Interns'];

class AttendanceTab extends StatefulWidget {
  const AttendanceTab({super.key});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> with RealtimeRefreshMixin {
  // Fallback only — live pushes (see RealtimeRefreshMixin) cover the normal case;
  // this just guards against a missed/dropped push.
  static const _autoRefreshInterval = Duration(seconds: 60);

  OfficeAttendance? _data;
  String? _selectedDepartment;
  DateTime _selectedDate = businessToday();
  String? _error;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) => _load());
    startListeningForRealtimeChanges();
  }

  @override
  void onRealtimeChanged() => _load();

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().adminApiService.officeAttendance(date: _selectedDate, department: _selectedDepartment);
      if (!mounted) return;
      setState(() {
        _data = result;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _selectDepartment(String? department) {
    setState(() => _selectedDepartment = department);
    _load();
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _data = null;
    });
    _load();
  }

  void _changeMonth(int delta) {
    _selectDate(DateTime(_selectedDate.year, _selectedDate.month + delta, 1));
  }

  /// Jumps straight to one specific employee's attendance (with an
  /// adjustable From/To range right there) regardless of whether they
  /// happen to be in today's roster below — the department chips + day
  /// roster only ever show one day at a time, so someone absent today (or
  /// simply not on this month's calendar) would otherwise be unreachable
  /// from this tab without a lot of manual day-by-day browsing.
  Future<void> _pickEmployee() async {
    List<AdminUser>? employees;
    try {
      final all = await context.read<AppProvider>().adminApiService.users();
      employees = all.where((u) => u.role == 'Employee').toList()..sort((a, b) => a.username.compareTo(b.username));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load employees: $e'), backgroundColor: AppColors.danger));
      }
      return;
    }
    if (!mounted) return;

    final chosen = await showModalBottomSheet<AdminUser>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EmployeePickerSheet(employees: employees!),
    );
    if (chosen == null || !mounted) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UserDayAttendanceScreen(userId: chosen.id, userName: chosen.fullName.isNotEmpty ? chosen.fullName : chosen.username, date: businessToday()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          _buildDepartmentChips(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickEmployee,
                icon: const Icon(Icons.person_search_rounded, size: 18),
                label: const Text('View one employee — pick a date range'),
              ),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (d == null) {
                  if (_error != null) {
                    return ListView(children: [const SizedBox(height: 100), Center(child: Text('Error: $_error'))]);
                  }
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildCalendarCard(d),
                    const SizedBox(height: 16),
                    _buildDayLog(d),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentChips() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.primarySoft)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip('All', _selectedDepartment == null, () => _selectDepartment(null)),
          for (final dep in _departments) _chip(dep, _selectedDepartment == dep, () => _selectDepartment(dep)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.primary : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.primaryDark),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarCard(OfficeAttendance d) {
    final days = d.calendar;
    final firstDate = DateTime.parse(days.first.date);
    final leading = (firstDate.weekday - 1) % 7;

    Color dotColor(String status) => switch (status) {
          'present' => AppColors.success,
          'late' => AppColors.warning,
          'absent' => AppColors.danger,
          'extra' => AppColors.alt,
          _ => Colors.transparent,
        };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primarySoft)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(d.monthLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _changeMonth(-1), visualDensity: VisualDensity.compact),
              IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _changeMonth(1), visualDensity: VisualDensity.compact),
            ],
          ),
          Text('Tap a day to see its log', style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Center(child: Text(w, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.inkMuted))),
              for (var i = 0; i < leading; i++) const SizedBox(),
              for (final day in days)
                _buildDayCell(day, dotColor(day.status)),
            ],
          ),
          const SizedBox(height: 12),
          // Actual head-count for the SELECTED day, not "how many days this
          // month were mostly-present days" — that month-wide tally reads
          // like an average and doesn't answer "how many people were here
          // today", which is what these three numbers are actually for.
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _legendDot('Present', AppColors.success, d.dayRoster.where((r) => r.status == 'OnFloor' || r.status == 'CheckedOut').length),
              _legendDot('Late', AppColors.warning, d.dayRoster.where((r) => r.status == 'Late').length),
              _legendDot('Absent', AppColors.danger, d.dayRoster.where((r) => r.status == 'Absent').length),
              _legendDot('Extra time', AppColors.alt, days.where((c) => c.status == 'extra').length),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(OfficeCalendarDay day, Color dotColor) {
    final date = DateTime.parse(day.date);
    final isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
    final dead = day.status == 'weekend' || day.status == 'future';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: dead ? null : () => _selectDate(date),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.primarySoft, width: isSelected ? 1.5 : 1),
          color: dead ? AppColors.surfaceLight : Colors.white,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${day.day}', style: TextStyle(fontSize: 11.5, color: dead ? AppColors.inkMuted : AppColors.ink)),
            const SizedBox(height: 2),
            Container(width: 5, height: 5, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(String label, Color color, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.inkMuted)),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildDayLog(OfficeAttendance d) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primarySoft)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Log · ${d.selectedDate}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('${d.activeEmployeeCount} people scheduled', style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (d.dayRoster.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No one scheduled for this day.', style: TextStyle(color: AppColors.inkMuted))))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(children: [for (final r in d.dayRoster) _attendanceRow(r)]),
            ),
        ],
      ),
    );
  }

  Widget _attendanceRow(AttendanceRosterRow a) {
    final initials = a.name.isNotEmpty ? a.name.substring(0, a.name.length >= 2 ? 2 : 1).toUpperCase() : '?';
    final (bg, fg, label) = switch (a.status) {
      'OnFloor' => (AppColors.success.withValues(alpha: 0.12), AppColors.success, 'On floor'),
      'CheckedOut' => (AppColors.primarySoft, AppColors.primaryDark, 'Checked out'),
      'Late' => (AppColors.warning.withValues(alpha: 0.12), AppColors.warning, 'Late'),
      'Off' => (AppColors.surfaceLight, AppColors.inkMuted, 'Off'),
      _ => (AppColors.danger.withValues(alpha: 0.1), AppColors.danger, 'Absent'),
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: a.userId > 0
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UserDayAttendanceScreen(userId: a.userId, userName: a.name, date: _selectedDate),
                ))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primaryDark)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                      '${a.department} · In ${a.checkInLabel ?? "—"} · Out ${a.checkOutLabel ?? "—"}',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                child: Text(label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeePickerSheet extends StatefulWidget {
  final List<AdminUser> employees;
  const _EmployeePickerSheet({required this.employees});

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.employees
        : widget.employees.where((u) => u.username.toLowerCase().contains(q) || u.fullName.toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select an employee', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              autofocus: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name or username'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final u = filtered[i];
                  final name = u.fullName.isNotEmpty ? u.fullName : u.username;
                  final initials = name.isNotEmpty ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase() : '?';
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: AppColors.primarySoft, child: Text(initials, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700))),
                    title: Text(name),
                    subtitle: Text('${u.department} · @${u.username}'),
                    onTap: () => Navigator.of(context).pop(u),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
