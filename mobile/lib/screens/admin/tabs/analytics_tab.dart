import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_theme.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../models/admin_models.dart';
import '../../../providers/app_provider.dart';
import '../../../widgets/section_card.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> with RealtimeRefreshMixin {
  static const _autoRefreshInterval = Duration(seconds: 90);

  AnalyticsData? _data;
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
  void dispose() {
    _autoRefreshTimer?.cancel();
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  @override
  void onRealtimeChanged() => _load();

  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().adminApiService.analytics();
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Builder(
        builder: (context) {
          final d = _data;
          if (d == null) {
            if (_error != null) {
              return ListView(children: [const SizedBox(height: 120), Center(child: Text('Could not load analytics: $_error'))]);
            }
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Analytics', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('Patterns worth acting on, last 30 days', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
              const SizedBox(height: 16),
              SectionCard(
                icon: Icons.pie_chart_rounded,
                title: 'Status split',
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 38,
                              sections: [
                                PieChartSectionData(value: d.status.present.toDouble(), color: AppColors.success, showTitle: false, radius: 20),
                                PieChartSectionData(value: d.status.late.toDouble(), color: AppColors.warning, showTitle: false, radius: 20),
                                PieChartSectionData(value: d.status.absent.toDouble(), color: AppColors.danger, showTitle: false, radius: 20),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${d.status.presentPct}%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                              Text('present', style: TextStyle(fontSize: 10, color: AppColors.inkMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendRow(color: AppColors.success, label: 'Present', value: d.status.presentPct),
                          const SizedBox(height: 6),
                          _LegendRow(color: AppColors.warning, label: 'Late', value: d.status.latePct),
                          const SizedBox(height: 6),
                          _LegendRow(color: AppColors.danger, label: 'Absent', value: d.status.absentPct),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                icon: Icons.groups_2_outlined,
                title: 'Department health',
                child: Column(
                  children: [
                    for (final dept in d.departmentHealth..sort((a, b) => b.ratePct.compareTo(a.ratePct)))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DeptBar(dept: dept),
                      ),
                    if (d.departmentHealth.isEmpty)
                      Text('No employees yet.', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                icon: Icons.lightbulb_outline_rounded,
                title: 'What the data says',
                child: Column(
                  children: [
                    for (final insight in d.insights)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _InsightCardView(insight: insight),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _LegendRow({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted))),
        Text('$value%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _DeptBar extends StatelessWidget {
  final DeptHealthRate dept;
  const _DeptBar({required this.dept});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(dept.department, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${dept.reportsLast30d} reports', style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            const SizedBox(width: 8),
            Text('${dept.ratePct}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: dept.ratePct / 100,
            minHeight: 6,
            backgroundColor: AppColors.primarySoft,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _InsightCardView extends StatelessWidget {
  final InsightCard insight;
  const _InsightCardView({required this.insight});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (insight.tone) {
      'alt' => (AppColors.alt.withValues(alpha: 0.1), AppColors.alt),
      'ok' => (AppColors.success.withValues(alpha: 0.1), AppColors.success),
      _ => (AppColors.warning.withValues(alpha: 0.12), AppColors.accentDark),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: fg)),
          const SizedBox(height: 5),
          Text(insight.body, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink)),
        ],
      ),
    );
  }
}
