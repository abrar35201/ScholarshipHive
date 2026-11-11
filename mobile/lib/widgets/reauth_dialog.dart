import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

/// Passwords are one-way hashed — nobody, including an Admin, can ever see an
/// existing password. Re-entering your OWN password is the closest available
/// safeguard before reaching a screen that lets you set a new one for someone
/// else. Returns true only if the admin's own password was confirmed correct.
Future<bool> confirmAdminPassword(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => const _ReauthDialog(),
  );
  return confirmed ?? false;
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog();

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  // Owned by this dialog's own State so Flutter only disposes it once this
  // widget is actually unmounted (i.e. after the dialog's exit animation
  // finishes) — disposing it manually right when the showDialog future
  // resolves races that animation and crashes with "A TextEditingController
  // was used after being disposed."
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await context.read<AppProvider>().authService.verifyOwnPassword(_controller.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _checking = false;
        _error = 'Incorrect password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Your Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter your own password to continue — this protects other users\' accounts from being changed without your confirmation.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Your Password',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _checking ? null : _confirm,
          child: _checking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Confirm'),
        ),
      ],
    );
  }
}
