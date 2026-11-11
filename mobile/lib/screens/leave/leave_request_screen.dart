import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/api_config.dart';
import '../../core/app_theme.dart';

/// Leave is intentionally separate from attendance: credential-check is server-side,
/// and employees can apply outside the office without being signed in/checking in.
class LeaveRequestScreen extends StatefulWidget {
  final String username;
  const LeaveRequestScreen({super.key, this.username = ''});
  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}
class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.username);
  final _password = TextEditingController();
  final _reason = TextEditingController();
  String _type = 'Full-Day Leave';
  DateTime _date = DateTime.now();
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  List<dynamic> _history = [];
  @override
  void dispose() { _username.dispose(); _password.dispose(); _reason.dispose(); super.dispose(); }
  String get _dateString => '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
  String _error(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) return '${data['message']}';
      return 'Network/server error: ${error.message}';
    }
    return error.toString();
  }
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    try {
      final result = await Dio().post('${ApiConfig.baseUrl}/leaves/apply', data: {
        'username': _username.text.trim(), 'password': _password.text,
        'leaveDate': _dateString, 'leaveType': _type, 'reason': _reason.text.trim(),
      });
      if (!mounted) return;
      setState(() { _message = '${result.data['message']}'; _reason.clear(); });
      await _refreshHistory();
    } catch (e) { if (mounted) setState(() => _message = _error(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _refreshHistory() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final response = await Dio().post('${ApiConfig.baseUrl}/leaves/status', data: {
        'username': _username.text.trim(), 'password': _password.text,
      });
      if (mounted) setState(() => _history = response.data as List<dynamic>);
    } catch (e) { if (mounted) setState(() => _message = _error(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Apply for Leave')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Form(
      key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Request leave from anywhere', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('Leave requests never check you in or bypass the approved office Wi-Fi for attendance.'),
        const SizedBox(height: 20),
        TextFormField(controller: _username, decoration: const InputDecoration(labelText: 'Username'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _password, obscureText: _hidePassword,
          decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(
            tooltip: _hidePassword ? 'Show password' : 'Hide password',
            icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hidePassword = !_hidePassword),
          )), validator: (v) => v == null || v.isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _type, decoration: const InputDecoration(labelText: 'Leave Type'), items: const [
          DropdownMenuItem(value: 'Full-Day Leave', child: Text('Full-Day Leave')),
          DropdownMenuItem(value: 'Half-Day Leave', child: Text('Half-Day Leave')),
        ], onChanged: (v) => setState(() => _type = v ?? _type)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () async {
          final date = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 730)));
          if (date != null) setState(() => _date = date);
        }, icon: const Icon(Icons.calendar_month), label: Text('Date: $_dateString')),
        const SizedBox(height: 12),
        TextFormField(controller: _reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason'), validator: (v) => v == null || v.trim().isEmpty ? 'Reason required' : null),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Submit Leave Request')),
        TextButton(onPressed: _busy ? null : _refreshHistory, child: const Text('Check My Leave Status')),
        if (_message != null) Padding(padding: const EdgeInsets.all(8), child: Text(_message!, style: const TextStyle(color: AppColors.primaryDark))),
        for (final row in _history) Card(child: ListTile(
          title: Text('${row['leaveType']} • ${row['leaveDate']}'),
          subtitle: Text('${row['reason']}'), trailing: Text('${row['status']}'))),
      ]),
    )),
  );
}
