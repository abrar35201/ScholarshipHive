import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/report.dart';
import '../../providers/app_provider.dart';
import '../../services/file_opener_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';
import 'my_reports_screen.dart';

class _Field {
  final String label;
  final TextEditingController controller = TextEditingController(text: '0');
  _Field(this.label);
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _maxFileSizeBytes = 10 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();

  late final Map<String, _Field> _fields = {
    'unreadChats': _Field('Unread Chats'),
    'newLeads': _Field('New Leads'),
    'qualifiedLeads': _Field('Qualified Leads'),
    'followUp': _Field('Follow Up'),
    'calls': _Field('Calls'),
    'potential': _Field('Potential'),
    'walkIns': _Field("Walk-in's"),
    'conversion': _Field('Conversion'),
  };
  final _textController = TextEditingController();

  bool _loading = true;
  String? _loadError;
  List<ReportFileRef> _existingFiles = [];
  final List<PlatformFile> _newFiles = [];
  bool _pickingFile = false;
  String? _pickError;
  int? _openingFileId;

  bool get _isTextReport => context.read<AppProvider>().currentUser?.department != 'Calling';

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.controller.dispose();
    }
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final reports = await context.read<AppProvider>().reportService.myReports();
      final editable = reports.where((r) => r.isEditable);
      final today = editable.isEmpty ? null : editable.first;
      if (today != null) {
        _fields['unreadChats']!.controller.text = today.unreadChats.toString();
        _fields['newLeads']!.controller.text = today.newLeads.toString();
        _fields['qualifiedLeads']!.controller.text = today.qualifiedLeads.toString();
        _fields['followUp']!.controller.text = today.followUp.toString();
        _fields['calls']!.controller.text = today.calls.toString();
        _fields['potential']!.controller.text = today.potential.toString();
        _fields['walkIns']!.controller.text = today.walkIns.toString();
        _fields['conversion']!.controller.text = today.conversion.toString();
        _textController.text = today.textContent ?? '';
        _existingFiles = today.files;
      }
    } catch (e) {
      _loadError = 'Could not load today\'s report: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _browseFiles() async {
    setState(() {
      _pickingFile = true;
      _pickError = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.bytes == null) {
          setState(() => _pickError = '"${file.name}" could not be read on this device.');
          continue;
        }
        if (file.size > _maxFileSizeBytes) {
          setState(() => _pickError = '"${file.name}" is too large (max 10 MB).');
          continue;
        }
        setState(() => _newFiles.add(file));
      }
    } catch (_) {
      setState(() => _pickError = 'Could not read that file.');
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  void _removeNewFile(PlatformFile file) => setState(() => _newFiles.remove(file));

  Future<void> _openExistingFile(ReportFileRef file) async {
    setState(() => _openingFileId = file.id);
    try {
      final bytes = await context.read<AppProvider>().reportService.downloadMyReportFile(file.id);
      await FileOpenerService.openBytes(bytes, file.fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _openingFileId = null);
    }
  }

  int _intOf(String key) => int.tryParse(_fields[key]!.controller.text.trim()) ?? 0;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = _isTextReport
        ? await context.read<AppProvider>().submitReport(
            textContent: _textController.text.trim(),
            newFiles: _newFiles,
          )
        : await context.read<AppProvider>().submitReport(
            unreadChats: _intOf('unreadChats'),
            newLeads: _intOf('newLeads'),
            qualifiedLeads: _intOf('qualifiedLeads'),
            followUp: _intOf('followUp'),
            calls: _intOf('calls'),
            potential: _intOf('potential'),
            walkIns: _intOf('walkIns'),
            conversion: _intOf('conversion'),
            newFiles: _newFiles,
          );

    if (success && mounted) {
      setState(() {
        _existingFiles = [
          ..._existingFiles,
          ..._newFiles.map((f) => ReportFileRef(id: -1, fileName: f.name, uploadedAt: DateTime.now())),
        ];
        _newFiles.clear();
      });
      // The id: -1 placeholders above are cosmetic only (for immediate display);
      // refetch so file ids/download links are accurate for the rest of this session.
      unawaited(_loadToday());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report saved.'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Past reports',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyReportsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You can update this as many times as you like today. From tomorrow, today\'s entry becomes read-only.',
                        style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 18),
                      if (provider.errorMessage != null || _pickError != null || _loadError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDECEC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _loadError ?? _pickError ?? provider.errorMessage!,
                            style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SectionCard(
                        icon: _isTextReport ? Icons.article_outlined : Icons.bar_chart_rounded,
                        title: _isTextReport ? "Today's report" : "Today's numbers",
                        child: _isTextReport
                            ? TextFormField(
                                controller: _textController,
                                maxLines: 10,
                                minLines: 6,
                                decoration: const InputDecoration(
                                  labelText: 'Write your report',
                                  alignLabelWithHint: true,
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: _CounterField(label: 'Leads handled', controller: _fields['newLeads']!.controller, large: true)),
                                      const SizedBox(width: 12),
                                      Expanded(child: _CounterField(label: 'Closed', controller: _fields['conversion']!.controller, large: true)),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      for (final key in _fields.keys)
                                        if (key != 'newLeads' && key != 'conversion')
                                          SizedBox(
                                            width: (MediaQuery.of(context).size.width - 20 * 2 - 32 - 10) / 2,
                                            child: _CounterField(label: _fields[key]!.label, controller: _fields[key]!.controller),
                                          ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 14),
                      SectionCard(
                        icon: Icons.attach_file_rounded,
                        title: 'Attachments',
                        child: Column(
                          children: [
                            for (final f in _existingFiles)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(f.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                    ),
                                    if (f.id == -1)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                      )
                                    else if (_openingFileId == f.id)
                                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    else
                                      IconButton(
                                        icon: const Icon(Icons.open_in_new_rounded, size: 20),
                                        onPressed: () => _openExistingFile(f),
                                        tooltip: 'Open',
                                      ),
                                  ],
                                ),
                              ),
                            for (final f in _newFiles)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.attach_file_rounded, color: AppColors.primary, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(f.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      onPressed: () => _removeNewFile(f),
                                      tooltip: 'Remove',
                                    ),
                                  ],
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _pickingFile ? null : _browseFiles,
                                icon: _pickingFile
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.add_rounded, size: 20),
                                label: const Text('Attach file(s)'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: 'Save Report',
                        isLoading: provider.isBusy,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// A number field for the day's KPIs — a real keyboard-editable text field
/// (numbers only, capped at 3 digits so a mistyped extra digit can't silently
/// record e.g. 4440 leads instead of 44) plus +/- steppers for quick
/// one-off adjustments without needing the keyboard at all.
class _CounterField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final bool large;

  const _CounterField({required this.label, required this.controller, this.large = false});

  @override
  State<_CounterField> createState() => _CounterFieldState();
}

class _CounterFieldState extends State<_CounterField> {
  int get _value => int.tryParse(widget.controller.text) ?? 0;

  void _adjust(int delta) {
    setState(() => widget.controller.text = (_value + delta).clamp(0, 999).toString());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: widget.large ? 16 : 12, vertical: widget.large ? 14 : 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: TextStyle(color: AppColors.inkMuted, fontSize: widget.large ? 12.5 : 11)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: widget.large ? 26 : 17, fontWeight: FontWeight.w700, color: AppColors.ink),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ),
              _stepperButton(Icons.remove_rounded, () => _adjust(-1)),
              const SizedBox(width: 6),
              _stepperButton(Icons.add_rounded, () => _adjust(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.primarySoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: widget.large ? 18 : 15, color: AppColors.primaryDark),
        ),
      ),
    );
  }
}
