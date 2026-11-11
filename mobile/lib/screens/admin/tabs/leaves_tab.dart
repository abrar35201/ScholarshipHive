import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api_config.dart';
import '../../../providers/app_provider.dart';
class LeavesTab extends StatefulWidget {
  const LeavesTab({super.key});
  @override State<LeavesTab> createState() => _LeavesTabState();
}
class _LeavesTabState extends State<LeavesTab> {
  List<dynamic> _rows = [];
  String? _error;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  Future<void> _load() async {
    try {
      final rows = await context.read<AppProvider>().api.getList('${ApiConfig.baseUrl}/leaves/admin');
      if (mounted) setState(() { _rows = rows; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  Future<void> _decide(int id, String decision) async {
    try {
      await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/leaves/admin/$id/decision', {'decision': decision});
      await _load();
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: _load,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      if (_rows.isEmpty) const Text('No leave requests yet.'),
      for (final l in _rows) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${l['fullName']} (${l['username']})', style: Theme.of(context).textTheme.titleMedium),
          Text('${l['leaveType']} • ${l['leaveDate']}'),
          Text('Reason: ${l['reason']}'),
          Text('Status: ${l['status']}'),
          if (l['status'] == 'Pending') Row(children: [
            TextButton(onPressed: () => _decide(l['id'] as int, 'Approved'), child: const Text('Approve')),
            TextButton(onPressed: () => _decide(l['id'] as int, 'Rejected'), child: const Text('Reject')),
          ]),
        ]))),
    ]));
}
