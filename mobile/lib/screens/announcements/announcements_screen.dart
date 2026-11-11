import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}
class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<dynamic> _items = [];
  List<dynamic> _personalNotices = [];
  String? _error;
  bool _busy = false;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  Future<void> _load() async {
    try {
      final api = context.read<AppProvider>().api;
      final items = await api.getList('${ApiConfig.baseUrl}/announcements');
      List<dynamic> personal = [];
      try { personal = await api.getList('${ApiConfig.baseUrl}/user-notices'); }
      catch (_) { /* Older servers may not support personal notices yet. */ }
      if (mounted) setState(() { _items = items; _personalNotices = personal; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  bool get _canPost {
    final role = context.read<AppProvider>().currentUser?.role ?? '';
    return ['Admin','SuperAdmin','Owner','CountryHead','HeadOfMarketing','HeadOfProcessing','HeadOfCounselors','Receptionist'].contains(role);
  }
  bool _canEdit(Map<String,dynamic> item) {
    final user = context.read<AppProvider>().currentUser;
    if (user == null || !_canPost) return false;
    return ['Admin','Owner','SuperAdmin'].contains(user.role) || item['authorId'] == user.id;
  }
  Future<void> _edit([Map<String,dynamic>? item]) async {
    final title = TextEditingController(text: '${item?['title'] ?? ''}');
    final body = TextEditingController(text: '${item?['body'] ?? ''}');
    String department = '${item?['departmentName'] ?? 'Everyone'}';
    // Legacy combined announcements are still readable; editing requires a specific audience.
    if (department == 'MarketingAndInterns') department = 'Marketing';
    final role = context.read<AppProvider>().currentUser?.role ?? '';
    if (item == null && role == 'HeadOfProcessing') department = 'Processing';
    if (item == null && role == 'HeadOfCounselors') department = 'Calling';
    if (item == null && role == 'HeadOfMarketing') department = 'Marketing';
    if (item == null && role == 'Receptionist') department = 'Reception';
    final scoped = ['HeadOfCounselors','HeadOfProcessing','HeadOfMarketing','Receptionist'].contains(role);
    final save = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text(item == null ? 'New announcement' : 'Edit announcement'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 160, decoration: const InputDecoration(labelText: 'Title')),
          TextField(controller: body, maxLength: 3000, maxLines: 5, decoration: const InputDecoration(labelText: 'Important message')),
          DropdownButtonFormField<String>(initialValue: department,
            decoration: const InputDecoration(labelText: 'Audience'),
            items: ['Everyone','Calling','Processing','Others','Interns','Marketing','MarketingAndInterns','Reception']
              .where((v) => v != 'MarketingAndInterns' && (!scoped || (role == 'HeadOfMarketing' ? (v == 'Marketing' || v == 'Interns') : v == department)))
              .map((v) => DropdownMenuItem(value: v, child: Text(v == 'Calling' ? 'Counselors' : v))).toList(),
            onChanged: scoped && role != 'HeadOfMarketing' ? null : (v) => setDialog(() => department = v ?? department)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      )));
    if (save != true || !mounted) { title.dispose(); body.dispose(); return; }
    if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
      setState(() => _error = 'Title and announcement text are required.');
    } else {
      setState(() => _busy = true);
      final data = {'title':title.text.trim(),'body':body.text.trim(),
        'department':department == 'Everyone' ? null : ['Calling','Processing','Others','Interns','Marketing','MarketingAndInterns','Reception'].indexOf(department)};
      try {
        final api = context.read<AppProvider>().api;
        if (item == null) { await api.post('${ApiConfig.baseUrl}/announcements', data); }
        else { await api.put('${ApiConfig.baseUrl}/announcements/${item['id']}', data); }
        await _load();
      } catch (e) { if (mounted) setState(() => _error = '$e'); }
      finally { if (mounted) setState(() => _busy = false); }
    }
    title.dispose(); body.dispose();
  }
  Future<void> _delete(Map<String,dynamic> item) async {
    try { await context.read<AppProvider>().api.delete('${ApiConfig.baseUrl}/announcements/${item['id']}'); await _load(); }
    catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Announcements'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    floatingActionButton: _canPost ? FloatingActionButton.extended(onPressed: _busy ? null : () => _edit(),
      icon: const Icon(Icons.campaign_outlined), label: const Text('New announcement')) : null,
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      if (_items.isEmpty && _personalNotices.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No announcements yet.')),
      for (final notice in _personalNotices) Card(
        child: ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: Text('${notice['title'] ?? 'Shift update'}'),
          subtitle: Text('${notice['body'] ?? ''}\nBy ${notice['actorName'] ?? 'Management'}'),
          isThreeLine: true,
        ),
      ),
      for (final raw in _items) Builder(builder: (_) {
        final a = Map<String,dynamic>.from(raw as Map);
        return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.campaign_outlined), const SizedBox(width: 8), Expanded(child: Text('${a['title']}', style: Theme.of(context).textTheme.titleMedium))]),
          const SizedBox(height: 8), Text('${a['body']}'),
          const SizedBox(height: 8), Text('${a['departmentName']} • ${a['author']} (${a['authorRole'] ?? 'Unknown role'})'),
          if (_canEdit(a)) Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => _edit(a), child: const Text('Edit')),
            TextButton(onPressed: () => _delete(a), child: const Text('Delete')),
          ]),
        ])));
      }),
      const SizedBox(height: 75),
    ])),
  );
}
