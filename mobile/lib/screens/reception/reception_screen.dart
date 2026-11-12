import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../core/app_theme.dart';
import '../../providers/app_provider.dart';
import '../account/change_credentials_screen.dart';
import '../leave/leave_request_screen.dart';
import '../announcements/announcements_screen.dart';
import '../shift/shift_request_screen.dart';

/// Reception staff can manage visitor entries; the current app theme is retained.
/// All records live in the same database as the admin dashboard.
class ReceptionScreen extends StatefulWidget {
  const ReceptionScreen({super.key});
  @override
  State<ReceptionScreen> createState() => _ReceptionScreenState();
}
class _ReceptionScreenState extends State<ReceptionScreen> {
  List<dynamic> _visitors = [];
  String? _error;
  bool _busy = false;
  final _fullName = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _qualification = TextEditingController();
  final _country = TextEditingController();
  final _program = TextEditingController();
  final _counsellor = TextEditingController();
  final _remarks = TextEditingController();
  String _inquiryType = 'Walk-in';
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  @override
  void dispose() { for (final c in [_fullName, _contact, _email, _qualification, _country, _program, _counsellor, _remarks]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    try {
      final result = await context.read<AppProvider>().api.getList('${ApiConfig.baseUrl}/reception/visitors');
      if (mounted) setState(() { _visitors = result; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  Future<void> _create(BuildContext sheetContext) async {
    final name = _fullName.text.trim();
    final phone = _contact.text.trim().replaceAll(RegExp(r'[ -]'), '');
    final mail = _email.text.trim();
    String? validation;
    if (!RegExp(r"^[a-zA-Z][a-zA-Z .'-]{1,119}$").hasMatch(name)) {
      validation = 'Enter a valid full name (letters, at least 2 characters).';
    } else if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)) {
      validation = 'Enter a contact number with 7–15 digits.';
    } else if (mail.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail)) {
      validation = 'Enter a valid email or leave it empty.';
    }
    if (validation != null) {
      if (sheetContext.mounted) {
        await showDialog<void>(context: sheetContext, builder: (dialogContext) => AlertDialog(
          title: const Text('Please check visitor details'),
          content: Text(validation!),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
        ));
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/reception/visitors', {
        'fullName': _fullName.text.trim(), 'contact': _contact.text.trim(),
        'email': _email.text.trim(), 'qualification': _qualification.text.trim(),
        'country': _country.text.trim(), 'program': _program.text.trim(),
        'counsellor': _counsellor.text.trim(), 'remarks': _remarks.text.trim(),
        'inquiryType': _inquiryType,
      });
      _fullName.clear(); _contact.clear(); _email.clear(); _qualification.clear();
      _country.clear(); _program.clear(); _counsellor.clear(); _remarks.clear();
      if (mounted && sheetContext.mounted) Navigator.of(sheetContext).pop();
      if (mounted) await _load();
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _checkout(int id) async {
    try {
      await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/reception/visitors/$id/checkout', {});
      await _load();
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  void _showNewVisitor() => showModalBottomSheet<void>(context: context, isScrollControlled: true,
    showDragHandle: true, builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Register Visitor', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final field in <(String,TextEditingController)>[
          ('Full Name *', _fullName), ('Contact', _contact), ('Email', _email),
          ('Qualification', _qualification), ('Country', _country),
          ('Program', _program), ('Counsellor', _counsellor), ('Remarks', _remarks),
        ]) Padding(padding: const EdgeInsets.only(bottom: 9), child: TextField(
          controller: field.$2,
          keyboardType: field.$1 == 'Contact' ? TextInputType.phone : (field.$1 == 'Email' ? TextInputType.emailAddress : TextInputType.text),
          decoration: InputDecoration(labelText: field.$1 == 'Contact' ? 'Contact *' : field.$1))),
        DropdownButtonFormField<String>(initialValue: _inquiryType,
          decoration: const InputDecoration(labelText: 'Inquiry Type'),
          items: const [DropdownMenuItem(value:'Walk-in',child:Text('Walk-in')),
          DropdownMenuItem(value:'Call',child:Text('Call')),DropdownMenuItem(value:'Referral',child:Text('Referral'))],
          onChanged: (v) => setState(() => _inquiryType = v ?? 'Walk-in')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : () => _create(ctx), child: const Text('Save Visitor')),
      ])),
    ));
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    return Scaffold(appBar: AppBar(title: const Text('Reception'), actions: [
      IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())), icon: const Icon(Icons.campaign_outlined), tooltip: 'Announcements'),
      IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      IconButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ChangeCredentialsScreen())),
        icon: const Icon(Icons.manage_accounts_outlined),
        tooltip: 'Account Settings',
      ),
      IconButton(onPressed: () => context.read<AppProvider>().logout(), icon: const Icon(Icons.logout)),
    ]), floatingActionButton: FloatingActionButton.extended(onPressed: _showNewVisitor,
      icon: const Icon(Icons.person_add_alt_1), label: const Text('New Visitor')),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Welcome, ${provider.currentUser?.fullName ?? 'Reception'}',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primaryDark)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LeaveRequestScreen(username: provider.currentUser?.username ?? ''))),
          icon: const Icon(Icons.event_note), label: const Text('Apply for Leave')),
        OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShiftRequestScreen())),
          icon: const Icon(Icons.schedule_outlined), label: const Text('My Shift Requests')),
        if (_error != null) Padding(padding: const EdgeInsets.all(10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 14),
        Text('Visitor Log' , style: Theme.of(context).textTheme.titleMedium),
        for (final v in _visitors) Card(
          color: v['checkOutTime'] == null ? const Color(0xFFE7F8EF) : Colors.white,
          child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text('${v['fullName'] ?? ''}'),
          subtitle: Text(
            "${v['contact'] ?? ''}  •  ${v['inquiryType'] ?? 'Walk-in'} · ${v['country'] ?? ''} · ${v['program'] ?? ''}\nIn: ${v['checkInTime'] ?? ''}\nOut: ${v['checkOutTime'] ?? 'Currently inside'}\n${v['qualification'] ?? ''} ${v['counsellor'] ?? ''} ${v['remarks'] ?? ''}",
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            itemBuilder: (_) => [
              if (v['checkOutTime'] == null) const PopupMenuItem(value: 'checkout', child: Text('Check out visitor')),
            ],
            onSelected: (action) {
              if (action == 'checkout') { _checkout(v['id'] as int); }
            },
          ),
        )),
        if (_visitors.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('No visitor records yet.')),
        const SizedBox(height: 75),
      ])),
    );
  }
}
