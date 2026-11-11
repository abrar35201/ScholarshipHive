import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../widgets/gradient_scaffold_background.dart';
import '../../widgets/primary_button.dart';
import '../leave/leave_request_screen.dart';
import '../shift/shift_request_screen.dart';
import '../login/login_screen.dart';

class NetworkErrorScreen extends StatelessWidget {
  const NetworkErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isLocationIssue = provider.networkErrorCode == 'location_not_confirmed';

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isLocationIssue ? Icons.location_off_rounded : Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    isLocationIssue ? 'Check Your Location' : 'Check Your Router',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    provider.networkMessage ??
                        'This device is not connected to an approved network.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 36),
                  TextButton(onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LeaveRequestScreen())),
                    child: const Text('Apply for Leave (available anywhere)', style: TextStyle(color: Colors.white))),
                  TextButton(onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ShiftRequestScreen())),
                    child: const Text('Request a shift (available anywhere)', style: TextStyle(color: Colors.white))),
                  TextButton(onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: const Text('Sign in', style: TextStyle(color: Colors.white))),
                  PrimaryButton(
                    label: 'Try Again',
                    icon: Icons.refresh_rounded,
                    isLoading: provider.stage == AppStage.checkingNetwork,
                    color: Colors.white,
                    onPressed: () => context.read<AppProvider>().refreshNetworkAndSession(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
