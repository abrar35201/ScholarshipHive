import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../core/app_theme.dart';
import '../../core/api_config.dart';
import '../../core/attendance_cycles.dart';
import '../../core/business_day.dart';
import '../../core/realtime_refresh_mixin.dart';
import '../../core/shift_utils.dart';
import '../../models/admin_models.dart';
import '../../models/report.dart';
import '../../providers/app_provider.dart';
import '../../services/file_opener_service.dart';
import '../../widgets/reauth_dialog.dart';
import 'ai_assistant_screen.dart';
import 'tabs/users_tab.dart' show UserFormSheet;
import 'widgets/report_card.dart';

class UserDetailScreen extends StatefulWidget {
  final int userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> with RealtimeRefreshMixin {
  late Future<AdminUserDetail> _future;

  @override
  void initState() {
    super.initState();
    _load();
    startListeningForRealtimeChanges();
  }

  @override
  void dispose() {
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  // Fires on ANY live push (a shift edit from the Shifts tab, a profile edit
  // from Users, a fresh check-in/out) — so a screen left open on this same
  // user never keeps showing a stale shift window or attendance total behind
  // what an admin just changed elsewhere.
  @override
  void onRealtimeChanged() => _refresh();

  void _load() {
    _future = context.read<AppProvider>().adminApiService.userDetail(widget.userId);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _resetDevice(AdminUser user) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Reset registered phone?'),
      content: Text('Allow ${user.username} to register a replacement phone at next password login?'),
      actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Reset device'))]));
    if (yes != true || !mounted) return;
    try { await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/admin/users/${user.id}/reset-device', {}); await _refresh(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
  }

  Future<void> _edit(AdminUser user) async {
    // Editing can set a new password for this user — re-confirm it's really
    // the admin doing this, not just an unlocked/left-open phone.
    if (!await confirmAdminPassword(context)) return;
    if (!mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserFormSheet(existing: user),
    );
    if (saved == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminUserDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('User')),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final detail = snapshot.data!;
        final user = detail.profile;

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text(user.username),
              actions: [
                if (context.watch<AppProvider>().currentUser?.role == 'Admin')
                  IconButton(
                    icon: const Icon(Icons.smart_toy_outlined),
                    tooltip: 'Ask AI about this user',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AiAssistantScreen(scopedUserId: user.id, scopedUsername: user.username),
                      ),
                    ),
                  ),
                if (user.role == 'Employee') IconButton(icon: const Icon(Icons.phonelink_erase_outlined),
                  tooltip: 'Reset registered phone', onPressed: () => _resetDevice(user)),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(user)),
              ],
              bottom: const TabBar(tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Attendance'),
                Tab(text: 'History'),
                Tab(text: 'Reports'),
              ]),
            ),
            body: RefreshIndicator(
              onRefresh: _refresh,
              child: TabBarView(
                children: [
                  _OverviewTab(detail: detail),
                  _AttendanceList(items: detail.attendance),
                  _HistoryList(items: detail.history),
                  _ReportsList(items: detail.reports),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Highest todayAccumulatedMinutes ever seen per "userId_date" — survives
/// pull-to-refresh and re-navigating back into this screen (this file's
/// state persists for the app session), so a display value never regresses
/// regardless of the underlying cause. Keying by date means a genuinely new
/// business day starts this back at zero on its own, with no separate
/// day-boundary logic needed here.
final Map<String, int> _maxKnownAccumulatedMinutes = {};

int _flooredAccumulatedMinutes(int userId, String date, int fresh) {
  final key = '${userId}_$date';
  final floor = _maxKnownAccumulatedMinutes[key] ?? 0;
  final result = fresh > floor ? fresh : floor;
  _maxKnownAccumulatedMinutes[key] = result;
  return result;
}

class _OverviewTab extends StatelessWidget {
  final AdminUserDetail detail;
  const _OverviewTab({required this.detail});

  @override
  Widget build(BuildContext context) {
    final user = detail.profile;
    final dateFmt = DateFormat('yyyy-MM-dd hh:mm a');
    final name = user.fullName.isEmpty ? user.username : user.fullName;
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();

    // Today's own attendance row (if any) — the actual check-in this cycle is
    // anchored to, so a Night shift that started yesterday evening still gets
    // the right calendar date instead of jumping forward at midnight.
    final today = businessToday();
    final todayAttendanceMatches = detail.attendance.where((a) => DateUtils.isSameDay(DateTime.parse(a.date), today));
    final todayAttendance = todayAttendanceMatches.isEmpty ? null : todayAttendanceMatches.first;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primarySoft)),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.primaryDark)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text('@${user.username} · ${user.role}', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isActive ? AppColors.success.withValues(alpha: 0.12) : AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  user.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(color: user.isActive ? AppColors.success : AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (todayAttendance != null) ...[
          const SizedBox(height: 16),
          _AdminShiftProgressCard(
            checkInTime: todayAttendance.checkInTime,
            checkOutTime: todayAttendance.checkOutTime,
            shiftStart: parseShiftTimeOfDay(user.shiftStartTime),
            shiftTarget: shiftDuration(user.shiftStartTime, user.shiftEndTime),
            // Floored against the highest value ever seen for this user on
            // this business day — never shown going backward on screen no
            // matter what (a real data hiccup, a stale fetch racing a
            // fresher one, anything). Naturally resets on a genuinely new
            // business day since the cache key includes the date.
            accumulatedMinutes: _flooredAccumulatedMinutes(user.id, todayAttendance.date, detail.todayAccumulatedMinutes),
            stillOpen: detail.todayStillOpen,
          ),
        ],
        const SizedBox(height: 16),
        _InfoRow(label: 'Approval Status', value: user.isApproved ? 'Approved' : 'Pending Approval'),
        _InfoRow(label: 'Lock Status', value: user.isLocked ? 'Locked (too many failed logins)' : 'Not locked'),
        _InfoRow(label: 'Account Created', value: dateFmt.format(user.createdAt.toLocal())),
      ],
    );
  }
}

/// Admin-only shift readout — real accumulated presence (see
/// AttendanceDurationService), shown against this person's own fixed shift
/// window ("9:00 AM – 5:00 PM"), not whatever time they actually checked in
/// at. Unlike the employee's own home-screen bar (a plain wall-clock that
/// never pauses), this one reflects genuine presence: it stops the moment
/// they check out, and picks back up from that same total — not from zero —
/// if they reconnect later the same day.
class _AdminShiftProgressCard extends StatefulWidget {
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final TimeOfDay shiftStart;
  final Duration shiftTarget;
  final int accumulatedMinutes;
  final bool stillOpen;

  const _AdminShiftProgressCard({
    required this.checkInTime,
    required this.checkOutTime,
    required this.shiftStart,
    required this.shiftTarget,
    required this.accumulatedMinutes,
    required this.stillOpen,
  });

  @override
  State<_AdminShiftProgressCard> createState() => _AdminShiftProgressCardState();
}

class _AdminShiftProgressCardState extends State<_AdminShiftProgressCard> {
  Timer? _ticker;
  late DateTime _anchorAt;

  @override
  void initState() {
    super.initState();
    _anchorAt = DateTime.now();
    if (widget.stillOpen) {
      _ticker = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    }
  }

  @override
  void didUpdateWidget(_AdminShiftProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A pull-to-refresh delivered a fresh server total — re-anchor to it
    // rather than keep ticking forward from the previous (now stale) one.
    if (oldWidget.accumulatedMinutes != widget.accumulatedMinutes || oldWidget.stillOpen != widget.stillOpen) {
      _anchorAt = DateTime.now();
      _ticker?.cancel();
      _ticker = widget.stillOpen ? Timer.periodic(const Duration(minutes: 1), (_) => setState(() {})) : null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checkInLocal = widget.checkInTime.toLocal();
    final shiftStartAt = DateTime(checkInLocal.year, checkInLocal.month, checkInLocal.day, widget.shiftStart.hour, widget.shiftStart.minute);
    final shiftEndAt = shiftStartAt.add(widget.shiftTarget);

    // Frozen the moment the cycle isn't open any more — only ticks forward
    // locally between refreshes while [stillOpen] says there's a live cycle.
    final ticked = widget.stillOpen ? DateTime.now().difference(_anchorAt) : Duration.zero;
    final elapsedRaw = Duration(minutes: widget.accumulatedMinutes) + (ticked.isNegative ? Duration.zero : ticked);
    final elapsed = elapsedRaw > widget.shiftTarget ? widget.shiftTarget : elapsedRaw;
    final progress = (elapsed.inMinutes / widget.shiftTarget.inMinutes).clamp(0.0, 1.0);
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primarySoft)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Today's shift: ${DateFormat('h:mm a').format(shiftStartAt)} – ${DateFormat('h:mm a').format(shiftEndAt)}",
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              if (!widget.stillOpen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(99)),
                  child: const Text('Paused', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${hours}h ${minutes}m present',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.primarySoft,
              valueColor: AlwaysStoppedAnimation(widget.stillOpen ? AppColors.primary : AppColors.success),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('hh:mm a').format(shiftStartAt), style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5)),
              Text(DateFormat('hh:mm a').format(shiftEndAt), style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 15.5)),
          const Divider(height: 20),
        ],
      ),
    );
  }
}

class _AttendanceList extends StatelessWidget {
  final List<AdminAttendance> items;
  const _AttendanceList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('No attendance yet.'));
    final timeFmt = DateFormat('hh:mm a');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final a = items[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(a.date),
            subtitle: Text('In ${timeFmt.format(a.checkInTime.toLocal())}'
                '  ·  Out ${a.checkOutTime != null ? timeFmt.format(a.checkOutTime!.toLocal()) : "—"}'),
            trailing: Icon(
              a.reportSubmitted ? Icons.check_circle : Icons.pending_outlined,
              color: a.reportSubmitted ? Colors.green : Colors.orange,
            ),
          ),
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<LoginHistoryEntry> items;
  const _HistoryList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('No history yet.'));
    final byDay = groupHistoryByDay(items);
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final dayFmt = DateFormat('EEEE, d MMM yyyy');
    final timeFmt = DateFormat('hh:mm:ss a');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final cycles = byDay[day]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dayFmt.format(day), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 8),
              for (final c in cycles)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primarySoft),
                  ),
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
                            style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
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
  }
}

class _ReportsList extends StatefulWidget {
  final List<AdminReport> items;
  const _ReportsList({required this.items});

  @override
  State<_ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends State<_ReportsList> {
  int? _openingFileId;

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

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const Center(child: Text('No reports yet.'));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, i) => ReportCard(
        report: items[i],
        openingFileId: _openingFileId,
        onOpenFile: _openFile,
      ),
    );
  }
}
