import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../widgets/primary_button.dart';

/// Auditor-only — compiles findings across everyone's work into a titled
/// write-up with optional attached files, then uploads it for Admins to see.
class AuditReportSubmitScreen extends StatefulWidget {
  const AuditReportSubmitScreen({super.key});

  @override
  State<AuditReportSubmitScreen> createState() => _AuditReportSubmitScreenState();
}

class _AuditReportSubmitScreenState extends State<AuditReportSubmitScreen> {
  static const _maxFileSizeBytes = 10 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  final List<PlatformFile> _files = [];

  bool _submitting = false;
  bool _pickingFile = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _browseFiles() async {
    setState(() {
      _pickingFile = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.bytes == null) {
          setState(() => _error = '"${file.name}" could not be read on this device.');
          continue;
        }
        if (file.size > _maxFileSizeBytes) {
          setState(() => _error = '"${file.name}" is too large (max 10 MB).');
          continue;
        }
        setState(() => _files.add(file));
      }
    } catch (_) {
      setState(() => _error = 'Could not read that file.');
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  void _removeFile(PlatformFile file) => setState(() => _files.remove(file));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await context.read<AppProvider>().auditReportService.submit(
            title: _titleController.text.trim(),
            textContent: _textController.text.trim(),
            files: _files,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not upload: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Audit Report')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5)),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Weekly audit — Calling team'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _textController,
                  maxLines: 10,
                  minLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Findings',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Attachments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final f in _files)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(f.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => _removeFile(f),
                          tooltip: 'Remove',
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _pickingFile ? null : _browseFiles,
                  icon: _pickingFile
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file_rounded),
                  label: const Text('Attach file(s)'),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Upload Audit Report',
                  isLoading: _submitting,
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
