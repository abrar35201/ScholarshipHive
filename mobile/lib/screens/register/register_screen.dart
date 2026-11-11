import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/api_config.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../core/validators.dart';
import '../../providers/app_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  String _department = 'Calling';
  bool _asReception = false;
  String? _registerError;
  String _shiftType = 'Day';
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    if (_asReception) {
      try {
        await Dio().post('${ApiConfig.baseUrl}/auth/register-reception', data: {
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
          'fullName': _fullNameController.text.trim(),
          'bssid': '00:00:00:00:00:00',
        });
        if (!mounted) return;
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Registration Submitted'),
          content: const Text('Your reception account is pending admin approval.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ));
        if (mounted) Navigator.pop(context);
      } on DioException catch (e) {
        final data = e.response?.data;
        setState(() => _registerError = data is Map ? '${data['message'] ?? e.message}' : '${e.message}');
      }
      return;
    }
    final success = await context.read<AppProvider>().register(
          _usernameController.text.trim(),
          _passwordController.text,
          _fullNameController.text.trim(),
          _department,
          shiftType: _shiftType,
        );

    if (success && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Registration Submitted'),
          content: const Text(
            'An admin needs to approve your account before you can sign in. Please check back later.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        children: [
          // Same layered decorative-orb backdrop as the login screen — the two
          // screens sit back-to-back in the same flow and should read as one
          // continuous visual language, not two different app skins.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
              ),
            ),
          ),
          Positioned(
            top: -size.width * 0.35,
            left: -size.width * 0.3,
            child: _Orb(diameter: size.width * 0.95, color: const Color(0xFF22C3E6).withValues(alpha: 0.35)),
          ),
          Positioned(
            bottom: size.height * 0.28,
            right: -size.width * 0.32,
            child: _Orb(diameter: size.width * 0.75, color: AppColors.success.withValues(alpha: 0.28)),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _anim,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
                    .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create Account',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'An admin will need to approve you\nbefore you can sign in.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14.5, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 9,
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(topLeft: Radius.circular(36), topRight: Radius.circular(36)),
                        ),
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                        child: SingleChildScrollView(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(99))),
                                ),
                                const SizedBox(height: 20),
                                if (provider.errorMessage != null) ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(provider.errorMessage!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13.5)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                SwitchListTile.adaptive(
                                  title: const Text('Register as Receptionist'),
                                  subtitle: const Text('Reception account requires admin approval.'),
                                  value: _asReception, onChanged: (v) => setState(() => _asReception = v),
                                ),
                                if (_registerError != null) Text(_registerError!, style: const TextStyle(color: Colors.red)),
                                TextFormField(
                                  controller: _fullNameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Full Name',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                                ),
                                const SizedBox(height: 16),
                                if (!_asReception) DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _department,
                                  decoration: const InputDecoration(
                                    labelText: 'Department',
                                    prefixIcon: Icon(Icons.work_outline_rounded),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'Calling', child: Text('Calling')),
                                    DropdownMenuItem(value: 'Processing', child: Text('Processing')),
                                    DropdownMenuItem(value: 'Others', child: Text('Others')),
                                    DropdownMenuItem(value: 'Interns', child: Text('Interns')),
                                  ],
                                  onChanged: (v) => setState(() => _department = v ?? 'Calling'),
                                ),
                                const SizedBox(height: 16),
                                if (!_asReception) DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _shiftType,
                                  decoration: const InputDecoration(
                                    labelText: 'Shift',
                                    prefixIcon: Icon(Icons.schedule_outlined),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'Day', child: Text('Day (9:30 AM – 5:30 PM)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    DropdownMenuItem(value: 'Night', child: Text('Night (6:00 PM – 2:00 AM)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    DropdownMenuItem(value: 'Internship', child: Text('Internship (6:00 PM – 10:00 PM)', maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) => setState(() => _shiftType = v ?? 'Day'),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _usernameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Username',
                                    prefixIcon: Icon(Icons.person_outline_rounded),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    helperText: 'At least 8 characters, with upper/lowercase, a number, and a symbol',
                                    helperMaxLines: 2,
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  validator: Validators.strongPassword,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Confirm Password',
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v != _passwordController.text) return 'Passwords do not match';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: provider.isBusy ? null : _submit,
                                    child: provider.isBusy
                                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [Text('Register'), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, size: 18)],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final double diameter;
  final Color color;
  const _Orb({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
