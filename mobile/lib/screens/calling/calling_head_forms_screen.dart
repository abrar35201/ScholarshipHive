import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';

/// Calling department head only. Server independently enforces role and team scope.
class CallingHeadFormsScreen extends StatefulWidget {
  const CallingHeadFormsScreen({super.key});
  @override State<CallingHeadFormsScreen> createState() => _CallingHeadFormsScreenState();
}
class _CallingHeadFormsScreenState extends State<CallingHeadFormsScreen> {
  List<dynamic> _records = [];
  String? _error;
  bool _busy = false;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await context.read<AppProvider>().api.getList('${ApiConfig.baseUrl}/calling-head-forms');
      if (mounted) setState(() => _records = result);
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(int id) async {
    try {
      final detail = await context.read<AppProvider>().api.get('${ApiConfig.baseUrl}/calling-head-forms/$id');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CallingHeadFormDetail(data: detail)));
      if (mounted) await _load();
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calling form records'), actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))]),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Saved form drafts from Calling team. Generate a link to share the completed application details with authorized recipients.'),
      const SizedBox(height: 8),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      if (_records.isEmpty && !_busy) const Padding(padding: EdgeInsets.all(16), child: Text('No Calling form submissions yet.')),
      for (final raw in _records) Builder(builder: (_) {
        final item = Map<String, dynamic>.from(raw as Map);
        return Card(child: ListTile(
          title: Text('${item['applicantName'] ?? ''}'),
          subtitle: Text('${item['templateId'] ?? ''} · Employee: ${item['employeeName'] ?? ''}\n${item['shared'] == true ? 'Share link active' : 'No public link'}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open((item['id'] as num).toInt()),
        ));
      }),
    ])),
  );
}

class _CallingHeadFormDetail extends StatefulWidget {
  final Map<String, dynamic> data;
  const _CallingHeadFormDetail({required this.data});
  @override State<_CallingHeadFormDetail> createState() => _CallingHeadFormDetailState();
}
class _CallingHeadFormDetailState extends State<_CallingHeadFormDetail> {
  String? _link;
  String? _error;
  bool _busy = false;
  late bool _shared = widget.data['shared'] == true;
  Future<void> _generate() async {
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Generate private share link?'),
      content: const Text('Anyone with this link can read the applicant’s personal data. Share only with authorized people. Creating a new link disables any older link.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Generate'))]));
    if (accepted != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/calling-head-forms/${widget.data['id']}/share', {});
      if (mounted) setState(() { _link = result['url']?.toString(); _shared = true; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _revoke() async {
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Revoke share link?'),
      content: const Text('People with the old link will no longer be able to open the form.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoke'))]));
    if (accepted != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/calling-head-forms/${widget.data['id']}/revoke', {});
      if (mounted) setState(() { _link = null; _shared = false; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) {
    final answers = Map<String, dynamic>.from(widget.data['answers'] as Map? ?? {});
    return Scaffold(appBar: AppBar(title: Text(widget.data['applicantName']?.toString() ?? 'Form details')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${widget.data['templateId'] ?? ''} · ${widget.data['employeeName'] ?? ''}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text('Phone: ${widget.data['phone'] ?? ''}'), Text('Email: ${widget.data['email'] ?? ''}'),
        for (final value in answers.entries) ListTile(dense: true, title: Text(value.key), subtitle: Text('${value.value}')),
        const Divider(),
        const Text('Draft only, not signed consent. Do not publish applicant data openly.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _generate, icon: const Icon(Icons.link), label: const Text('Generate new share link')),
        if (_shared) OutlinedButton.icon(onPressed: _busy ? null : _revoke, icon: const Icon(Icons.link_off), label: const Text('Revoke share link')),
        if (_link != null) ...[
          const SizedBox(height: 12),
          SelectableText(_link!),
          const Text('Link shown only once. Copy and share through WhatsApp or another app.'),
          FilledButton.icon(onPressed: () async {
            try {
              await AndroidIntent(action: 'android.intent.action.SEND', type: 'text/plain',
                package: 'com.whatsapp', arguments: {'android.intent.extra.TEXT': _link}).launch();
            } catch (e) {
              await Clipboard.setData(ClipboardData(text: _link!));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp unavailable. Link copied to clipboard.')));
            }
          }, icon: const Icon(Icons.send), label: const Text('Send via WhatsApp')),
          OutlinedButton.icon(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _link!));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied. Paste it in WhatsApp or anywhere you need.')));
          }, icon: const Icon(Icons.copy), label: const Text('Copy share link')),
        ],
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      ]),
    );
  }
}
