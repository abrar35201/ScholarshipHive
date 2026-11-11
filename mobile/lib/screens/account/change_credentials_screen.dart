import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/validators.dart';
import '../../providers/app_provider.dart';
import '../../services/biometric_lock_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';

class ChangeCredentialsScreen extends StatefulWidget {
  const ChangeCredentialsScreen({super.key});

  @override
  State<ChangeCredentialsScreen> createState() => _ChangeCredentialsScreenState();
}

class _ChangeCredentialsScreenState extends State<ChangeCredentialsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newUsernameController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _obscure = true;
  bool _obscureCurrent = true;

  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  bool _biometricBusy = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppProvider>().currentUser;
    if (user != null) _newUsernameController.text = user.username;
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final supported = await BiometricLockService.isDeviceSupported();
    final username = context.read<AppProvider>().currentUser?.username ?? '';
    final enabled = await BiometricLockService.isEnabledFor(username);
    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _biometricEnabled = enabled;
    });
  }

  /// Turning it ON requires actually succeeding a real prompt first — not
  /// just flipping a switch — so nobody ends up "protected" by a lock they
  /// never confirmed this device could actually satisfy (no fingerprint
  /// enrolled, sensor trouble, etc.), which would otherwise just lock them
  /// out of their own app the next time it re-arms. Turning it OFF doesn't
  /// need that same confirmation — removing a lock is never the risky
  /// direction.
  Future<void> _onBiometricToggle(bool value) async {
    final provider = context.read<AppProvider>();
    final username = provider.currentUser?.username;
    if (username == null) return;
    setState(() => _biometricBusy = true);
    try {
      await provider.setFingerprintEnabled(username, value);
      if (mounted) setState(() => _biometricEnabled = value);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _biometricBusy = false);
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final provider = context.read<AppProvider>();
    final newUsername = _newUsernameController.text.trim();
    final unchangedUsername = newUsername == (provider.currentUser?.username ?? '');

    final success = await provider.changeCredentials(
      currentPassword: _currentPasswordController.text,
      newUsername: unchangedUsername ? null : newUsername,
      newPassword: _newPasswordController.text.isEmpty ? null : _newPasswordController.text,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credentials updated successfully.'), backgroundColor: AppColors.success),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Settings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                // Deliberately its own thing, above the password-confirmed form below —
                // this just talks to the phone's own fingerprint sensor, no account
                // password involved at all, so it shouldn't look like it's part of a
                // form that needs "Current Password" to take effect.
                SectionCard(
                  icon: Icons.fingerprint_rounded,
                  title: 'Security',
                  child: _biometricSupported
                      ? SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Fingerprint login'),
                          subtitle: const Text('After enrollment, type this username and use fingerprint to sign in. Password is required again if enrollment expires.'),
                          value: _biometricEnabled,
                          onChanged: _biometricBusy ? null : _onBiometricToggle,
                        )
                      : Text(
                          'Fingerprint login needs an enrolled phone fingerprint.',
                          style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                        ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Update your login details',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Confirm your current password to make changes.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                if (provider.errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      provider.errorMessage!,
                      style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SectionCard(
                  icon: Icons.badge_outlined,
                  title: 'Login details',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _newUsernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPasswordController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'New Password (leave blank to keep current)',
                          helperText: 'At least 8 characters, with upper/lowercase, a number, and a symbol',
                          helperMaxLines: 2,
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: Validators.optionalStrongPassword,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  icon: Icons.key_outlined,
                  title: 'Confirm it\'s you',
                  child: TextFormField(
                    controller: _currentPasswordController,
                    obscureText: _obscureCurrent,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required to confirm changes' : null,
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Save Changes',
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
