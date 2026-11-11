import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../models/admin_models.dart';
import '../../../providers/app_provider.dart';

const List<String> _departments = [
  'Calling',
  'Processing',
  'Others',
  'Interns',
];

/// Lets an admin set each employee's shift window — one at a time, or in
/// bulk for a whole department or an arbitrary multi-selected group.
/// Lateness everywhere in the app is judged against each person's own
/// ShiftStartTime (plus a 15-minute grace), not one fixed cutoff — see
/// DateTimeExtensions.IsLateFor on the backend.
class ShiftsTab extends StatefulWidget {
  const ShiftsTab({super.key});

  @override
  State<ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<ShiftsTab> with RealtimeRefreshMixin {
  static const _autoRefreshInterval = Duration(seconds: 60);

  List<AdminUser>? _users;
  String? _error;
  String? _selectedDepartment;
  final Set<int> _selectedIds = {};
  Timer? _autoRefreshTimer;
  bool _applying = false;

  TimeOfDay _bulkStart = const TimeOfDay(hour: 9, minute: 30);
  TimeOfDay _bulkEnd = const TimeOfDay(hour: 17, minute: 30);
  String _bulkShiftType = 'Day';

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
      final all = await context.read<AppProvider>().adminApiService.users();
      if (!mounted) return;
      setState(() {
        _users = all.where((u) => u.role == 'Employee').toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  List<AdminUser> get _visibleUsers {
    final users = _users ?? const [];
    if (_selectedDepartment == null) return users;
    return users.where((u) => u.department == _selectedDepartment).toList();
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial);

  Future<void> _editOne(AdminUser u) async {
    var start = _parseTimeOfDay(u.shiftStartTime);
    var end = _parseTimeOfDay(u.shiftEndTime);
    var type = u.shiftType;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${u.fullName.isNotEmpty ? u.fullName : u.username}\'s shift',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              _ShiftTypeToggle(
                value: type,
                onChanged: (v) => setSheetState(() => type = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await _pickTime(start);
                        if (picked != null) setSheetState(() => start = picked);
                      },
                      child: Text('Start: ${start.format(ctx)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await _pickTime(end);
                        if (picked != null) setSheetState(() => end = picked);
                      },
                      child: Text('End: ${end.format(ctx)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;
    try {
      await context.read<AppProvider>().adminApiService.setShift(
        userId: u.id,
        startTime: _formatTimeOfDay(start),
        endTime: _formatTimeOfDay(end),
        shiftType: type,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shift updated for ${u.username}.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update shift: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _applyBulk() async {
    final hasSelection = _selectedIds.isNotEmpty;
    final target = hasSelection
        ? '${_selectedIds.length} selected employee(s)'
        : _selectedDepartment != null
        ? 'everyone in $_selectedDepartment'
        : 'ALL employees';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply shift'),
        content: Text('Set this shift for $target?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _applying = true);
    try {
      await context.read<AppProvider>().adminApiService.setShiftBulk(
        userIds: _selectedIds.toList(),
        department: _selectedIds.isEmpty ? _selectedDepartment : null,
        startTime: _formatTimeOfDay(_bulkStart),
        endTime: _formatTimeOfDay(_bulkEnd),
        shiftType: _bulkShiftType,
      );
      setState(() => _selectedIds.clear());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift applied.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not apply shift: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          _buildDepartmentChips(),
          _buildBulkBar(),
          Expanded(
            child: Builder(
              builder: (context) {
                if (users == null) {
                  if (_error != null) {
                    return ListView(
                      children: [
                        const SizedBox(height: 100),
                        Center(child: Text('Error: $_error')),
                      ],
                    );
                  }
                  return const Center(child: CircularProgressIndicator());
                }
                final visible = _visibleUsers;
                if (visible.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('No employees here.')),
                    ],
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _shiftRow(visible[i]),
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
          _chip(
            'All',
            _selectedDepartment == null,
            () => setState(() => _selectedDepartment = null),
          ),
          for (final dep in _departments)
            _chip(
              dep,
              _selectedDepartment == dep,
              () => setState(() => _selectedDepartment = dep),
            ),
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
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.primaryDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBulkBar() {
    final target = _selectedIds.isNotEmpty
        ? '${_selectedIds.length} selected'
        : _selectedDepartment != null
        ? 'all in $_selectedDepartment'
        : 'ALL employees';

    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.surfaceLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Apply to: $target',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await _pickTime(_bulkStart);
                    if (picked != null) setState(() => _bulkStart = picked);
                  },
                  child: Text(
                    'Start: ${_bulkStart.format(context)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await _pickTime(_bulkEnd);
                    if (picked != null) setState(() => _bulkEnd = picked);
                  },
                  child: Text(
                    'End: ${_bulkEnd.format(context)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ShiftTypeToggle(
                  value: _bulkShiftType,
                  onChanged: (v) => setState(() => _bulkShiftType = v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _applying ? null : _applyBulk,
                child: _applying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shiftRow(AdminUser u) {
    final selected = _selectedIds.contains(u.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editOne(u),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedIds.add(u.id);
                  } else {
                    _selectedIds.remove(u.id);
                  }
                }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.fullName.isNotEmpty ? u.fullName : u.username,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${u.department} · ${u.shiftType} shift · ${formatShiftTime(u.shiftStartTime)} – ${formatShiftTime(u.shiftEndTime)}',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TimeOfDay _parseTimeOfDay(String hhmmss) {
  final parts = hhmmss.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 9,
    minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
  );
}

String _formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _ShiftTypeToggle extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;
  const _ShiftTypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final t in const ['Day', 'Night', 'Internship'])
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t == value ? AppColors.ink : AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
