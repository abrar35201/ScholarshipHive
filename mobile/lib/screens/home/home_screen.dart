import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/app_provider.dart';
import '../account/change_credentials_screen.dart';
import '../attendance/my_attendance_screen.dart';
import '../announcements/announcements_screen.dart';
import '../report/report_screen.dart';
import '../shift/shift_request_screen.dart';
import '../calling/calling_forms_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  Future<void> _handleLogout() async {
    final provider = context.read<AppProvider>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log Out')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final error = await provider.logout();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.danger),
      );
    }
  }

  /// The other 3 destinations are full-screen actions, not persistent tabs —
  /// push, then land back on Today once the user returns.
  Future<void> _navigateTo(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() => _navIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser;

    if (provider.justMarkedAttendance) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance marked for today ✓'), backgroundColor: AppColors.success),
        );
        context.read<AppProvider>().acknowledgeAttendanceMarked();
      });
    }

    final now = DateTime.now();
    final hour = now.hour;
    final timeOfDay = hour < 12 ? 'Morning' : (hour < 17 ? 'Afternoon' : 'Evening');
    final firstName = user?.fullName.isNotEmpty == true ? user!.fullName.split(' ').first : (user?.username ?? '');

    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 28),
                decoration: const BoxDecoration(
                  gradient: AppColors.gradient,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
                                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$timeOfDay, $firstName',
                                style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          offset: const Offset(0, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          icon: CircleAvatar(
                            radius: 17,
                            backgroundColor: Colors.white.withValues(alpha: 0.22),
                            child: Text(
                              (user?.username.isNotEmpty == true ? user!.username[0] : '?').toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              enabled: false,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(user?.fullName.isNotEmpty == true ? user!.fullName : (user?.username ?? ''), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text('@${user?.username ?? ''}', style: TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(value: 'account', child: ListTile(leading: Icon(Icons.manage_accounts_outlined), title: Text('Account Settings'), contentPadding: EdgeInsets.zero)),
                            const PopupMenuItem(value: 'announcements', child: ListTile(leading: Icon(Icons.campaign_outlined), title: Text('Announcements'), contentPadding: EdgeInsets.zero)),
                            const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout_rounded, color: AppColors.danger), title: Text('Log Out', style: TextStyle(color: AppColors.danger)), contentPadding: EdgeInsets.zero)),
                          ],
                          onSelected: (value) {
                            if (value == 'account') {
                              _navigateTo(const ChangeCredentialsScreen());
                            } else if (value == 'announcements') {
                              _navigateTo(const AnnouncementsScreen());
                            } else if (value == 'logout') {
                              _handleLogout();
                            }
                          },
                        ),
                      ],
                    ),
                    if (provider.todayCheckInTime != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF6EE7B7), shape: BoxShape.circle)),
                            const SizedBox(width: 7),
                            const Text('Checked in on approved office network', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _navigateTo(const ReportScreen()),
                        icon: Icon(provider.reportSubmitted ? Icons.edit_note_rounded : Icons.description_outlined),
                        label: Text(
                          provider.reportSubmitted ? "Edit today's report" : 'File report and check out',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(color: AppColors.primarySoft),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _navigateTo(const MyAttendanceScreen()),
                      icon: const Icon(Icons.event_available_outlined, color: AppColors.primaryDark, size: 19),
                      label: const Text('View my attendance', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
                    ),
                    if (user?.role == 'Employee' && user?.department == 'Calling') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => _navigateTo(const CallingFormsScreen()),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Calling Country Forms'),
                      ),
                    ],
                    if (user != null && !(user.role == 'Admin' && user.username.toLowerCase() == 'admin')) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => _navigateTo(const ShiftRequestScreen()),
                        icon: const Icon(Icons.schedule_outlined),
                        label: const Text('My Shift Requests'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) {
          if (i == 0) {
            setState(() => _navIndex = 0);
            return;
          }
          setState(() => _navIndex = i);
          switch (i) {
            case 1:
              _navigateTo(const MyAttendanceScreen());
            case 2:
              _navigateTo(const ReportScreen());
            case 3:
              _navigateTo(const ChangeCredentialsScreen());
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.event_available_outlined), selectedIcon: Icon(Icons.event_available), label: 'History'),
          NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Report'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'You'),
        ],
      ),
    );
  }
}

