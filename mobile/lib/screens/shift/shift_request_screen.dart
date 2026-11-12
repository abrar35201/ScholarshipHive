import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

class ShiftRequestScreen extends StatefulWidget {
  final String username;
  final bool credentialMode;
  const ShiftRequestScreen({super.key, this.username = '', this.credentialMode = false});
  @override State<ShiftRequestScreen> createState() => _ShiftRequestScreenState();
}

class _ShiftRequestScreenState extends State<ShiftRequestScreen> {
  late final _username = TextEditingController(text: widget.username);
  final _password = TextEditingController();
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 30);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 30);
  int _shift = 0;
  bool _busy = false;
  String? _message;
  List<dynamic> _requests = [];

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }
  @override void dispose() { _username.dispose(); _password.dispose(); _reason.dispose(); super.dispose(); }

  String _time(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  String _shiftName(dynamic value) => switch (value) { 1 || 'Night' => 'Night', 2 || 'Internship' => 'Internship', _ => 'Day' };
  String _date(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse('$value')?.toLocal();
    return parsed == null ? '$value' : '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    if (widget.credentialMode && (_username.text.trim().isEmpty || _password.text.isEmpty)) {
      if (mounted) setState(() { _requests = []; _message = 'Enter your username and password to check your request status.'; });
      return;
    }
    try {
      final result = widget.credentialMode
          ? (await Dio().post('${ApiConfig.baseUrl}/shift-requests/remote/mine', data: {'username': _username.text.trim(), 'password': _password.text})).data as List<dynamic>
          : await context.read<AppProvider>().api.getList('${ApiConfig.baseUrl}/shift-requests/mine');
      if (mounted) setState(() { _requests = result; _message = null; });
    } on DioException catch (e) {
      if (mounted) setState(() => _message = e.response?.data is Map ? '${e.response?.data['message'] ?? 'Could not verify account.'}' : 'Could not reach the server. Check your connection.');
    } catch (e) { if (mounted) setState(() => _message = '$e'); }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _message = null; });
    try {
      final request = {
        'shiftType': _shift, 'start': _time(_start), 'end': _time(_end), 'reason': _reason.text.trim(),
      };
      if (widget.credentialMode) {
        await Dio().post('${ApiConfig.baseUrl}/shift-requests/remote/apply', data: {
          ...request, 'username': _username.text.trim(), 'password': _password.text,
        });
      } else {
        await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/shift-requests/apply', request);
      }
      _reason.clear();
      if (mounted) setState(() => _message = 'Shift request submitted. Status: Pending.');
      await _load();
    } on DioException catch (e) {
      if (mounted) setState(() => _message = e.response?.data is Map ? '${e.response?.data['message'] ?? 'Could not submit request.'}' : 'Could not reach the server. Check your connection.');
    } catch (e) { if (mounted) setState(() => _message = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked != null) setState(() { if (start) { _start = picked; } else { _end = picked; } });
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.credentialMode ? 'Request For Custom Shift' : 'My Shift Requests'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.credentialMode) ...[
          TextFormField(controller: _username, keyboardType: TextInputType.text, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username'), validator: (v) => v == null || v.trim().isEmpty ? 'Username required' : null),
          TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), validator: (v) => v == null || v.isEmpty ? 'Password required' : null),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.history), label: const Text('Check My Status'))),
        ],
        Text('Request a custom shift', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(initialValue: _shift, decoration: const InputDecoration(labelText: 'Shift Type'),
          items: const [DropdownMenuItem(value: 0, child: Text('Day')), DropdownMenuItem(value: 1, child: Text('Night')), DropdownMenuItem(value: 2, child: Text('Internship'))], onChanged: (v) => setState(() => _shift = v ?? 0)),
        Row(children: [Expanded(child: TextButton(onPressed: () => _pick(true), child: Text('Start ${_time(_start)}'))), Expanded(child: TextButton(onPressed: () => _pick(false), child: Text('End ${_time(_end)}')))]),
        TextFormField(controller: _reason, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Reason'), validator: (v) => v == null || v.trim().isEmpty ? 'Reason required' : null),
        const SizedBox(height: 8), FilledButton(onPressed: _busy ? null : _submit, child: const Text('Send for Approval')),
      ])))),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_message!)),
      Text('Request history', style: Theme.of(context).textTheme.titleLarge),
      if (_requests.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No shift requests yet.')),
      for (final raw in _requests) Builder(builder: (context) {
        final request = Map<String, dynamic>.from(raw as Map);
        final status = '${request['status'] ?? 'Pending'}';
        final color = status == 'Approved' ? Colors.green : status == 'Rejected' ? Colors.red : Colors.orange;
        return Card(child: ListTile(isThreeLine: true,
          title: Text('${_shiftName(request['shiftType'])} · ${request['start'] ?? ''}–${request['end'] ?? ''}'),
          subtitle: Text('${request['reason'] ?? ''}\nSubmitted ${_date(request['createdAt'])}\n${request['reviewedAt'] == null ? 'Decision date pending' : 'Decision ${_date(request['reviewedAt'])}'}${status == 'Rejected' && request['adminNote'] != null ? '\nReason: ${request['adminNote']}' : ''}'),
          trailing: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ));
      }),
    ])),
  );
}
