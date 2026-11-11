import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../models/admin_models.dart';
import '../../../providers/app_provider.dart';
import '../../../widgets/section_card.dart';
import '../user_day_attendance_screen.dart';
import '../user_detail_screen.dart';

const List<String> _periods = ['day', 'week', 'month'];

class TodayTab extends StatefulWidget {
  /// Jumps the parent AdminHomeScreen's bottom-nav to another tab index
  /// (1=Attendance, 2=Reports, 3=Team) — lets a stat card act as a shortcut
  /// to the section it's summarizing, not just a static number.
  final void Function(int tabIndex)? onNavigate;

  /// Network's actual tab index — varies by role and by whatever else is in
  /// the tab list, so the parent computes it rather than this widget
  /// guessing a literal that silently goes stale (see AdminHomeScreen).
  final int networkTabIndex;

  const TodayTab({super.key, this.onNavigate, required this.networkTabIndex});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> with RealtimeRefreshMixin {
  // Fallback only — live pushes (see RealtimeRefreshMixin) cover the normal case;
  // this just guards against a missed/dropped push.
  static const _autoRefreshInterval = Duration(seconds: 60);

  AdminDashboard? _data;
  String? _error;
  String _period = 'day';
  Timer? _autoRefreshTimer;
  bool _loading = false;
  bool _reloadAfterCurrent = false;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) => _load());
    startListeningForRealtimeChanges();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  @override
  void onRealtimeChanged() => _load();

  Future<void> _load() async {
    if (_loading) {
      _reloadAfterCurrent = true;
      return;
    }
    _loading = true;
    final requestedPeriod = _period;
    try {
      final result = await context.read<AppProvider>().adminApiService.dashboard(period: requestedPeriod);
      if (!mounted) return;
      if (requestedPeriod == _period) {
        setState(() { _data = result; _error = null; });
      } else {
        _reloadAfterCurrent = true;
      }
    } catch (e) {
      if (mounted && requestedPeriod == _period) setState(() => _error = e.toString());
    } finally {
      _loading = false;
      if (_reloadAfterCurrent && mounted) {
        _reloadAfterCurrent = false;
        unawaited(_load());
      }
    }
  }

  void _selectPeriod(String p) {
    setState(() {
      _period = p;
      _data = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ['Admin','SuperAdmin','Owner','CountryHead','HeadOfMarketing','HeadOfProcessing'].contains(context.watch<AppProvider>().currentUser?.role);

    return RefreshIndicator(
      onRefresh: _load,
      child: Builder(
        builder: (context) {
          final d = _data;
          if (d == null) {
            if (_error != null) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text('Could not load dashboard: $_error')),
                ],
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(child: Text('Today', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                  _PeriodSeg(selected: _period, onSelect: _selectPeriod),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  _MetricCard(
                    label: 'On the floor',
                    value: '${d.checkedInNow}',
                    sublabel: 'of ${d.totalActiveEmployees} · ${d.awayCount} away',
                    onTap: () => widget.onNavigate?.call(1),
                  ),
                  _MetricCard(
                    label: 'Average arrival',
                    value: d.averageArrivalLabel,
                    sublabel: d.averageArrivalSublabel,
                    trendValue: d.averageArrivalTrendMinutes,
                    trendSuffix: 'm',
                    invertTrendColor: true,
                    onTap: () => widget.onNavigate?.call(1),
                  ),
                  _MetricCard(
                    label: 'Reports filed',
                    value: '${d.reportsFiledRate}%',
                    sublabel: '${d.reportsFiledFraction} shifts',
                    trendValue: d.reportsFiledTrendPct,
                    trendSuffix: '%',
                    onTap: () => widget.onNavigate?.call(2),
                  ),
                  _MetricCard(
                    label: 'Punctuality rate',
                    value: '${d.punctualityRatePct}%',
                    sublabel: 'on-time · Day/Night shifts',
                    trendValue: d.punctualityRateTrendPct,
                    trendSuffix: '%',
                    onTap: () => widget.onNavigate?.call(1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (d.pendingApprovals > 0)
                _AlertTile(icon: Icons.person_add_alt_1_rounded, text: '${d.pendingApprovals} user(s) waiting for approval', onTap: () => widget.onNavigate?.call(3)),
              if (isAdmin && d.pendingNetworks > 0)
                _AlertTile(icon: Icons.wifi_tethering_rounded, text: '${d.pendingNetworks} network(s) waiting for approval', onTap: () => widget.onNavigate?.call(widget.networkTabIndex)),
              if (isAdmin && !d.pushNotificationsEnabled)
                _AlertTile(
                  icon: Icons.notifications_off_rounded,
                  text: 'Push notifications (FCM) are disabled — background auto check-in can\'t self-recover without this',
                  onTap: null,
                ),
              if (d.shiftHealth.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionCard(
                  icon: Icons.groups_rounded,
                  title: 'Shift-wise attendance (last 30 days)',
                  child: Column(
                    children: [
                      for (var i = 0; i < d.shiftHealth.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _ShiftHealthRow(shift: d.shiftHealth[i]),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SectionCard(
                icon: Icons.bar_chart_rounded,
                // Always the trailing 7 days regardless of the Day/Week/Month
                // toggle above — a fixed recent-trend reference, not itself
                // scoped by the period selector (that's what the stat cards
                // and the day-by-day breakdown below are for).
                title: 'Recent headcount (last 7 days)',
                child: SizedBox(
                  height: 140,
                  child: d.weeklyHeadcount.every((p) => p.value == 0)
                      ? Center(child: Text('No attendance yet this week.', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)))
                      : BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, meta) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= d.weeklyHeadcount.length) return const SizedBox();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(d.weeklyHeadcount[i].label, style: TextStyle(fontSize: 10.5, color: AppColors.inkMuted)),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups: [
                              for (var i = 0; i < d.weeklyHeadcount.length; i++)
                                BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: d.weeklyHeadcount[i].value,
                                    color: d.weeklyHeadcount[i].value > 0 ? AppColors.primary : AppColors.primarySoft,
                                    width: 18,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ]),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                icon: Icons.show_chart_rounded,
                title: 'Check-ins through the day (7 AM – 7 AM)',
                child: SizedBox(
                  height: 140,
                  child: d.arrivalCurve.every((p) => p.value == 0)
                      ? Center(child: Text('No check-ins yet today.', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)))
                      // The full business day is 24 hourly points now (was a fixed
                      // 08:00-10:30 morning-only window that made every Night/
                      // Internship-shift check-in invisible) — that's too dense to
                      // label legibly at the screen's own width, so this scrolls
                      // horizontally instead of squeezing every label together.
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: d.arrivalCurve.length * 42.0,
                            height: 140,
                            child: LineChart(
                              LineChartData(
                                gridData: const FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      // Without an explicit interval, fl_chart picks its own tick
                                      // spacing for this axis — often smaller than 1 unit for a
                                      // short x-range like this, so the same point (v.toInt())
                                      // got queried at both v=0 and v=0.5, v=1 and v=1.5, etc.,
                                      // rendering every label twice back-to-back.
                                      interval: 1,
                                      getTitlesWidget: (v, meta) {
                                        final i = v.toInt();
                                        if (i < 0 || i >= d.arrivalCurve.length || i != v) return const SizedBox();
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(d.arrivalCurve[i].label, style: TextStyle(fontSize: 9.5, color: AppColors.inkMuted)),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: [for (var i = 0; i < d.arrivalCurve.length; i++) FlSpot(i.toDouble(), d.arrivalCurve[i].value)],
                                    isCurved: true,
                                    color: AppColors.primary,
                                    barWidth: 2.5,
                                    dotData: const FlDotData(show: true),
                                    belowBarData: BarAreaData(show: true, color: AppColors.primarySoft.withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                icon: Icons.groups_2_outlined,
                title: 'Live roster',
                child: Column(
                  children: [
                    for (final r in d.roster)
                      _RosterRow(entry: r),
                    if (d.roster.isEmpty)
                      Text('No active employees yet.', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (d.dailyBreakdown.isNotEmpty) ...[
                const SizedBox(height: 14),
                SectionCard(
                  icon: Icons.view_day_outlined,
                  title: _period == 'month' ? 'Attendance by day (last 30 days)' : 'Attendance by day (last 7 days)',
                  child: Column(
                    children: [
                      for (var i = 0; i < d.dailyBreakdown.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 24, thickness: 1.4, color: AppColors.ink),
                        _DayBreakdownBlock(day: d.dailyBreakdown[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PeriodSeg extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  const _PeriodSeg({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in _periods)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: p == selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  p[0].toUpperCase() + p.substring(1),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p == selected ? AppColors.ink : AppColors.inkMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String sublabel;
  final int? trendValue;
  final String trendSuffix;
  final bool invertTrendColor;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.sublabel,
    this.trendValue,
    this.trendSuffix = '%',
    this.invertTrendColor = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trend = trendValue;
    final trendUp = (trend ?? 0) > 0;
    final trendGood = invertTrendColor ? !trendUp : trendUp;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primarySoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5, fontWeight: FontWeight.w600))),
                  if (trend != null && trend != 0)
                    Flexible(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: trendGood ? AppColors.success.withValues(alpha: 0.12) : AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${trend > 0 ? "+" : ""}$trend$trendSuffix',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: trendGood ? AppColors.success : AppColors.danger),
                      ),
                    )),
                ],
              ),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(sublabel, style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const _AlertTile({required this.icon, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFDF3E4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF3DCA8)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accentDark, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: AppColors.accentDark, fontSize: 13.5))),
              Icon(Icons.chevron_right_rounded, color: AppColors.accentDark, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  final RosterEntry entry;
  // When set, tapping opens that specific day's check-in/check-out log
  // instead of the user's full profile — used by the day-by-day breakdown
  // below, where the day being looked at matters more than the whole history.
  final DateTime? date;
  const _RosterRow({required this.entry, this.date});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (entry.status) {
      'OnFloor' => (AppColors.success.withValues(alpha: 0.12), AppColors.success, 'On floor'),
      'CheckedOut' => (AppColors.primarySoft, AppColors.primaryDark, 'Checked out'),
      'Late' => (AppColors.warning.withValues(alpha: 0.12), AppColors.warning, 'Late'),
      _ => (AppColors.danger.withValues(alpha: 0.1), AppColors.danger, 'Absent'),
    };
    final initials = entry.name.isNotEmpty ? entry.name.substring(0, entry.name.length >= 2 ? 2 : 1).toUpperCase() : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: entry.userId > 0
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => date != null
                      ? UserDayAttendanceScreen(userId: entry.userId, userName: entry.name, date: date!)
                      : UserDetailScreen(userId: entry.userId),
                ))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.primaryDark)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(entry.department, style: TextStyle(color: AppColors.inkMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (entry.checkInLabel != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('In ${entry.checkInLabel}', style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5)),
                    Text('Out ${entry.checkOutLabel ?? "—"}', style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5)),
                  ],
                ),
              const SizedBox(width: 8),
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

/// One shift's attendance/punctuality snapshot — genuine, company-wide numbers
/// (Day/Night only; Internship shift is the interns, deliberately left out
/// everywhere this appears) replacing the old Calling-only "leads handled" card.
class _ShiftHealthRow extends StatelessWidget {
  final ShiftHealth shift;
  const _ShiftHealthRow({required this.shift});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${shift.shiftLabel} shift', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            Text('${shift.presentToday} of ${shift.activeEmployees} today', style: TextStyle(color: AppColors.inkMuted, fontSize: 11)),
            const SizedBox(width: 8),
            Text('${shift.attendanceRatePct30d}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: shift.attendanceRatePct30d / 100,
            minHeight: 6,
            backgroundColor: AppColors.primarySoft,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: 4),
        Text('${shift.punctualityRatePct30d}% punctual', style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5)),
      ],
    );
  }
}

class _DayBreakdownBlock extends StatelessWidget {
  final DayRoster day;
  const _DayBreakdownBlock({required this.day});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(day.date);
    final present = day.roster.where((r) => r.status != 'Absent').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(day.dateLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
            Text('$present of ${day.roster.length} present', style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 4),
        if (day.roster.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('No one scheduled.', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
          )
        else
          for (final r in day.roster) _RosterRow(entry: r, date: date),
      ],
    );
  }
}
