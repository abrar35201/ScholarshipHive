import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

/// Calling-team forms. The server independently verifies Calling membership
/// for every API request; hiding this screen from other departments is not security.
class CallingFormsScreen extends StatefulWidget {
  const CallingFormsScreen({super.key});
  @override State<CallingFormsScreen> createState() => _CallingFormsScreenState();
}
class _CallingFormsScreenState extends State<CallingFormsScreen> {
  List<dynamic> _templates = [];
  List<dynamic> _entries = [];
  bool _busy = false;
  String? _error;
  @override void initState() {super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load());}

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final api = context.read<AppProvider>().api;
      final templates = await api.getList('${ApiConfig.baseUrl}/calling-forms/templates');
      final entries = await api.getList('${ApiConfig.baseUrl}/calling-forms/submissions');
      if (mounted) setState(() { _templates = templates; _entries = entries; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _openPdf(Map<String, dynamic> template) async {
    try {
      final id = template['id'].toString();
      final bytes = await context.read<AppProvider>().api.getBytes('${ApiConfig.baseUrl}/calling-forms/templates/$id/pdf');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/calling-form-$id.pdf';
      await File(path).writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(path, type: 'application/pdf');
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open PDF: ${result.message}')));
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _newDraft(Map<String, dynamic> template) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallingFormEditScreen(template: template)));
    if (mounted) _load();
  }

  Future<void> _detail(int id) async {
    try {
      final data = await context.read<AppProvider>().api.get('${ApiConfig.baseUrl}/calling-forms/submissions/$id');
      if (!mounted) return;
      final answers = Map<String, dynamic>.from(data['answers'] as Map? ?? {});
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(data['applicantName']?.toString() ?? 'Saved draft'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Phone: ${data['phone'] ?? ''}'), Text('Email: ${data['email'] ?? ''}'),
          for (final entry in answers.entries) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${entry.key}: ${entry.value}')),
          const SizedBox(height: 12), const Text('Draft only. Original agreement must be reviewed and signed separately.', style: TextStyle(fontSize: 12)),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calling Forms'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Choose a country and policy form for a client', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Saved entries are drafts, not signed consent. Review the original PDF before collecting any signature.', style: TextStyle(fontSize: 12)),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      for (final raw in _templates) Builder(builder: (ctx) {
        final template = Map<String, dynamic>.from(raw as Map);
        return Card(child: ListTile(
          title: Text(template['name']?.toString() ?? ''),
          subtitle: Text(template['country']?.toString() ?? ''),
          onTap: () => _newDraft(template),
          trailing: IconButton(onPressed: () => _openPdf(template), icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Read original PDF'),
        ));
      }),
      const SizedBox(height: 16),
      Text('My saved drafts', style: Theme.of(context).textTheme.titleMedium),
      for (final raw in _entries) Builder(builder: (ctx) {
        final entry = Map<String, dynamic>.from(raw as Map);
        return Card(child: ListTile(
          title: Text(entry['applicantName']?.toString() ?? ''),
          subtitle: Text('${entry['templateId'] ?? ''} · ${entry['createdAt'] ?? ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _detail((entry['id'] as num).toInt()),
        ));
      }),
    ])),
  );
}

class CallingFormEditScreen extends StatefulWidget {
  final Map<String, dynamic> template;
  const CallingFormEditScreen({super.key, required this.template});
  @override State<CallingFormEditScreen> createState() => _CallingFormEditScreenState();
}
class _CallingFormEditScreenState extends State<CallingFormEditScreen> {
  static const fields = <String>[
    'surname','givenName','dateOfBirth','gender','nationality','maritalStatus',
    'domicileCity','placeOfBirth','cnic','cnicIssueDate','cnicExpiryDate',
    'passportNumber','passportIssueDate','passportExpiryDate','whatsapp',
    'address','city','province','postalCode','emergencyContactName',
    'emergencyContactPhone','guardianRelationship','qualification','degreeTitle',
    'university','degreeStartDate','degreeEndDate','educationCountry',
    'rollNumber','cgpaOrPercentage','college','board','marksObtained','totalMarks',
    'program','intake','consultancyFee','advancePaid','notes',
    'matricMarks','intermediateMarks','universityOffer','englishTestResult',
    'visaStatus','spouseName','spousePassportNumber','spouseContact',
    'universityApplicationFee','clientInitials','counselorName'
  ];
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _answers = <String, TextEditingController>{for (final f in fields) f: TextEditingController()};
  bool _busy = false;
  String? _error;
  @override void dispose() { _name.dispose(); _phone.dispose(); _email.dispose(); for(final c in _answers.values) {c.dispose();} super.dispose(); }
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final response = await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/calling-forms/submissions', {
        'templateId': widget.template['id'],
        'applicantName': _name.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim(),
        'answers': {for (final e in _answers.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()},
      });
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']?.toString() ?? 'Draft saved')));
        Navigator.of(context).pop();
      }
    } catch (e) {if(mounted)setState(() => _error = '$e');}
    finally {if(mounted)setState(() => _busy = false);}
  }
  String _label(String name) => name.replaceAllMapped(RegExp(r'[A-Z]'), (match) => ' ${match.group(0)}').trim();
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.template['name']?.toString() ?? 'New calling form')),
    body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Application draft only — review and sign original PDF separately.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      TextFormField(controller: _name, maxLength: 120, decoration: const InputDecoration(labelText: 'Applicant full name *'),
        validator: (v) => (v??'').trim().length < 2 ? 'Enter applicant full name' : null),
      TextFormField(controller: _phone, maxLength: 40, keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Phone *'), validator: (v) => (v??'').trim().length < 7 ? 'Enter phone number' : null),
      TextFormField(controller: _email, maxLength: 150, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
      for(final field in fields) TextFormField(controller: _answers[field], maxLength: 350,
        decoration: InputDecoration(labelText: _label(field))),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 12),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving...' : 'Save application draft')),
    ])),
  );
}
