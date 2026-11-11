import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/app_provider.dart';
import '../register/register_screen.dart';
import 'forgot_password_screen.dart';
import '../leave/leave_request_screen.dart';
import '../shift/shift_request_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    if (provider.lastUsername != null) {
      _usernameController.text = provider.lastUsername!;
    }
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
    _showForcedLogoutNoticeIfAny(provider);
  }

  /// A borrowed-device session that just got force-ended (see
  /// AuthController.Checkin's device_borrow_expired check) lands here with no
  /// other explanation visible — without this, it would look exactly like the
  /// app randomly signed someone out for no reason.
  void _showForcedLogoutNoticeIfAny(AppProvider provider) {
    final notice = provider.consumeForcedLogoutNotice();
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notice), duration: const Duration(seconds: 6)),
      );
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final username = _usernameController.text.trim();
    final provider = context.read<AppProvider>();
    await provider.signIn(username, _passwordController.text);

  }

  Future<void> _tryFingerprintFromLogin() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your username first.')),
      );
      return;
    }
    await context.read<AppProvider>().biometricLogin(username);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        children: [
          // Layered decorative orbs, matching the web admin panel's auth-page
          // radial gradients — a full-bleed backdrop rather than a plain
          // gradient rectangle behind a centered card.
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
                    const SizedBox(height: 28),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10))],
                              ),
                              padding: const EdgeInsets.all(10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset('assets/logo_square.png', fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'ScholarshipHive',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sign in to start your shift — attendance,\nreports, and everything in between.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14.5, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 7,
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(topLeft: Radius.circular(36), topRight: Radius.circular(36)),
                        ),
                        padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
                        child: SingleChildScrollView(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(99))),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Welcome back',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Enter your details to continue',
                                  style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5),
                                ),
                                const SizedBox(height: 24),
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
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      onPressed: _tryFingerprintFromLogin,
                                      icon: const Icon(Icons.fingerprint_rounded),
                                      color: AppColors.primary,
                                      tooltip: 'Use enrolled fingerprint',
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => ForgotPasswordScreen(initialUsername: _usernameController.text.trim()),
                                      )),
                                      child: const Text('Forgot password?'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: provider.isBusy ? null : _submit,
                                    child: provider.isBusy
                                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [Text('Sign In'), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, size: 18)],
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Center(child: TextButton(
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaveRequestScreen(username: _usernameController.text.trim()))),
                                  child: const Text('Apply for Leave'),
                                )),
                                Center(child: TextButton(
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShiftRequestScreen(username: _usernameController.text.trim()))),
                                  child: const Text('Request For Custom Shift'),
                                )),
                                Center(
                                  child: TextButton(
                                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                                    child: const Text("New here? Create an account"),
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
