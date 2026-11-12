import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

class DepartmentEmployeeMonthScreen extends StatefulWidget {
  final int employeeId;
  final String name;
  final DateTime initialMonth;
  const DepartmentEmployeeMonthScreen({super.key, required this.employeeId, required this.name, required this.initialMonth});

  @override
  State<DepartmentEmployeeMonthScreen> createState() => _DepartmentEmployeeMonthScreenState();
}

class _DepartmentEmployeeMonthScreenState extends State<DepartmentEmployeeMonthScreen> {
  late DateTime _month;
  Map<String, dynamic>? _detail;
  String? _error;
  bool _loading = false;
  static const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _hours(dynamic input) {
    final value = input is num ? input.toInt() : int.tryParse('$input') ?? 0;
    return '${value ~/ 60}h ${value % 60}m';
  }

  String _time(dynamic value) {
    if (value == null) return '—';
    final utc = DateTime.tryParse('$value');
    if (utc == null) return '—';
    final local = utc.toUtc().add(const Duration(hours: 5));
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final min = local.minute.toString().padLeft(2, '0');
    return '$hour:$min ${local.hour < 12 ? 'AM' : 'PM'} PKT';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/team-scope/employees/${widget.employeeId}/monthly-hours')
          .replace(queryParameters: {'year': '${_month.year}', 'month': '${_month.month}'});
      final data = await context.read<AppProvider>().api.get(uri.toString());
      if (mounted) setState(() { _detail = data; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isCurrentMonth = _month.year == today.year && _month.month == today.month;
    final days = (_detail?['days'] as List<dynamic>?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(widget.name), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: [
        Card(child: Row(children: [
          IconButton(onPressed: _loading ? null : () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${months[_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: _loading || isCurrentMonth ? null : () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
        ])),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_detail != null) ...[
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_detail!['department'] ?? ''}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Working: ${_hours(_detail!['totalMinutes'])}'),
            Text('Days worked: ${_detail!['daysWorked'] ?? 0}'),
            Text('Gap: ${_hours(_detail!['totalGapMinutes'])}'),
          ]))),
          for (final raw in days) Builder(builder: (context) {
            final day = Map<String, dynamic>.from(raw as Map);
            final date = '${day['date'] ?? ''}';
            return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Check-in: ${_time(day['firstCheckInUtc'])}'),
                Text('Check-out: ${_time(day['lastCheckOutUtc'])}'),
                Text('Working: ${_hours(day['minutes'])}   Gap: ${_hours(day['gapMinutes'])}'),
                if (day['stillOpen'] == true) const Text('Shift still open', style: TextStyle(color: Colors.teal)),
              ],
            )));
          }),
          const Padding(padding: EdgeInsets.all(8), child: Text('Recorded event times are in Pakistan time; attendance day changes at 7 AM. Monthly hours follow the existing gap rules.', style: TextStyle(fontSize: 12))),
        ],
      ])),
    );
  }
}
