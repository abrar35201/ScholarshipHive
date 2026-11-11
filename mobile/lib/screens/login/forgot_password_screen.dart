import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_exception.dart';
import '../../core/app_theme.dart';
import '../../providers/app_provider.dart';

/// Queues a "forgot password" request for admin approval — never resets the
/// password directly. Only succeeds when submitted from the account's own
/// registered device (see AuthController.ForgotPassword); any other device
/// gets a clear rejection rather than a silent failure.
class ForgotPasswordScreen extends StatefulWidget {
  final String? initialUsername;
  const ForgotPasswordScreen({super.key, this.initialUsername});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.initialUsername ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final message = await context.read<AppProvider>().authService.forgotPassword(
            username: _usernameController.text.trim(),
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      setState(() {
        _successMessage = message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _successMessage != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    const Icon(Icons.mark_email_read_outlined, color: AppColors.success, size: 56),
                    const SizedBox(height: 16),
                    Text('Request sent', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_successMessage!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkMuted)),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to Sign In')),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Reset your password', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Best done from your own phone — the one you normally use to check in. '
                        'Your new password goes to an admin for approval before it takes effect; '
                        'from a different phone, they may reach out to confirm it\'s really you first.',
                        style: TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline_rounded)),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_outline_rounded)),
                        validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Text('Send Request'),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
