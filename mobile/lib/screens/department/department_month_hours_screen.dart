import 'department_employee_month_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

class DepartmentMonthHoursScreen extends StatefulWidget {
  const DepartmentMonthHoursScreen({super.key});
  @override State<DepartmentMonthHoursScreen> createState() => _DepartmentMonthHoursScreenState();
}

class _DepartmentMonthHoursScreenState extends State<DepartmentMonthHoursScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _summary;
  String? _error;
  bool _loading = false;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _hours(dynamic raw) {
    final minutes = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/team-scope/monthly-hours').replace(queryParameters: {
        'year': '${_month.year}', 'month': '${_month.month}',
      });
      final result = await context.read<AppProvider>().api.get(uri.toString());
      if (mounted) setState(() { _summary = result; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
    _load();
  }

  @override Widget build(BuildContext context) {
    final employees = _summary?['employees'] as List<dynamic>? ?? const [];
    final current = DateTime.now();
    final isCurrentMonth = _month.year == current.year && _month.month == current.month;
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Department Hours'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), child: Row(children: [
          IconButton(onPressed: _loading ? null : () => _changeMonth(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous month'),
          Expanded(child: Text(DateFormatCompat.month(_month), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge)),
          IconButton(onPressed: _loading || isCurrentMonth ? null : () => _changeMonth(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next month'),
        ]))),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_loading) const LinearProgressIndicator(),
        if (_summary != null) ...[
          Text('${_summary!['department'] ?? 'Department'} · ${_summary!['employees']?.length ?? 0} employees', style: Theme.of(context).textTheme.titleMedium),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Select an employee to view their individual daily attendance and working hours.')),
          const SizedBox(height: 8),
          if (employees.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No active employees are assigned to this department.'))),
          for (final raw in employees) Builder(builder: (context) {
            final employee = Map<String, dynamic>.from(raw as Map);
            final name = '${employee['name'] ?? ''}';
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(name),
              subtitle: Text('${employee['department'] ?? ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DepartmentEmployeeMonthScreen(
                  employeeId: (employee['userId'] as num).toInt(),
                  name: name,
                  initialMonth: _month,
                ),
              )),
            ));
          }),
        ],
      ])),
    );
  }
}

class DateFormatCompat {
  static String month(DateTime date) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${names[date.month - 1]} ${date.year}';
  }
}
