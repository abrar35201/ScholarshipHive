import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/gradient_scaffold_background.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(size: 88),
                const SizedBox(height: 24),
                Text(
                  'ScholarshipHive',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Checking your network…',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
