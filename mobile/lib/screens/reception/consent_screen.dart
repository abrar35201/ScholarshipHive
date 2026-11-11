import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';
class ReceptionConsentScreen extends StatefulWidget {
  final Map<String, dynamic>? visitor;
  const ReceptionConsentScreen({super.key, this.visitor});
  @override State<ReceptionConsentScreen> createState() => _ReceptionConsentScreenState();
}
class _ReceptionConsentScreenState extends State<ReceptionConsentScreen> {
  final _name = TextEditingController();
  final _family = TextEditingController();
  final _city = TextEditingController(text: 'Lahore');
  final _cnic = TextEditingController();
  final _phone = TextEditingController();
  final _passport = TextEditingController();
  final _address = TextEditingController();
  final _qualification = TextEditingController();
  final _counselor = TextEditingController();
  final _fee = TextEditingController(text: '250000');
  String _policy = '50% Refundable (Standard)';
  List<dynamic> _rows = [];
  String? _message;
  bool _busy = false;
  @override void initState() {
    super.initState();
    final visitor = widget.visitor;
    if (visitor != null) {
      _name.text = '${visitor['fullName'] ?? ''}';
      _phone.text = '${visitor['contact'] ?? ''}';
      _qualification.text = '${visitor['qualification'] ?? ''}';
      _counselor.text = '${visitor['counsellor'] ?? ''}';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }
  @override void dispose() { for (final c in [_name, _family, _city, _cnic, _phone, _passport, _address, _qualification, _counselor, _fee]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    try {
      final rows = await context.read<AppProvider>().api.getList('${ApiConfig.baseUrl}/reception/consents');
      if (mounted) setState(() { _rows = rows; _message = null; });
    } catch (e) { if (mounted) setState(() => _message = '$e'); }
  }
  Future<void> _save(BuildContext sheetContext) async {
    if (_name.text.trim().isEmpty) { setState(() => _message = 'Client name required.'); return; }
    setState(() => _busy = true);
    try {
      await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/reception/consents', {
        'visitorRecordId': widget.visitor?['id'],
        'clientFullName': _name.text.trim(), 'familyName': _family.text.trim(),
        'domicileCity': _city.text.trim(), 'cnicNumber': _cnic.text.trim(),
        'phoneNumber': _phone.text.trim(), 'passportNumber': _passport.text.trim(),
        'fullAddress': _address.text.trim(), 'qualificationDetails': _qualification.text.trim(),
        'counselorName': _counselor.text.trim(), 'policyVariant': _policy,
        'totalPackageFee': int.tryParse(_fee.text.trim()) ?? -1,
      });
      if (mounted && sheetContext.mounted) Navigator.of(sheetContext).pop();
      if (mounted) await _load();
    } catch (e) { if (mounted) setState(() => _message = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _sign(int id) async {
    try {
      await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/reception/consents/$id/signed', {});
      await _load();
    } catch (e) { if (mounted) setState(() => _message = '$e'); }
  }
  void _createDialog() => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
    builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('New Consent Draft', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final field in <(String,TextEditingController)>[
          ('Client Full Name', _name), ('Family Name', _family), ('City', _city),
          ('CNIC', _cnic), ('Phone', _phone), ('Passport', _passport),
          ('Address', _address), ('Qualification', _qualification),
          ('Counselor', _counselor), ('Package Fee (PKR)', _fee),
        ]) Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(
          controller: field.$2, decoration: InputDecoration(labelText: field.$1))),
        DropdownButtonFormField<String>(initialValue: _policy,
          decoration: const InputDecoration(labelText: 'Policy Variant'),
          items: const [
            DropdownMenuItem(value:'50% Refundable (Standard)',child:Text('50% Refundable')),
            DropdownMenuItem(value:'30% Refundable (Regional Scholarship)',child:Text('30% Refundable')),
            DropdownMenuItem(value:'Non-Refundable (Processing & Admin)',child:Text('Non-Refundable')),
            DropdownMenuItem(value:'IELTS & CENT-S Specific Variant',child:Text('IELTS / CENT-S')),
          ], onChanged: (v) => setState(() => _policy = v ?? _policy)),
        const SizedBox(height: 12),
        const Text('Draft only: sending/signing documents requires a separate verified workflow.'),
        FilledButton(onPressed: _busy ? null : () => _save(ctx), child: const Text('Save Draft')),
      ])),
    ));
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reception Consents')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _createDialog,
      icon: const Icon(Icons.note_add_outlined), label: const Text('New Draft')),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      if (_message != null) Text(_message!, style: const TextStyle(color: Colors.red)),
      if (_rows.isEmpty) const Text('No consent drafts yet.'),
      for (final row in _rows) Card(child: ListTile(
        title: Text('${row['clientFullName']}'),
        subtitle: Text('${row['policyVariant']} • PKR ${row['totalPackageFee']}'),
        trailing: row['status'] == 'Signed' ? const Icon(Icons.check_circle_outline, color: Colors.green)
          : TextButton(onPressed: () => _sign(row['id'] as int), child: const Text('Mark Signed')),
      )),
    ])),
  );
}
