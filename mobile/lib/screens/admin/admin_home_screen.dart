import 'dart:async';
import '../../core/api_config.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../models/user.dart';
import '../account/change_credentials_screen.dart';
import 'ai_assistant_screen.dart';
import '../announcements/announcements_screen.dart';
import 'shift_requests_screen.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/leaves_tab.dart';
import 'tabs/attendance_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/hours_tab.dart';
import 'tabs/network_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/shifts_tab.dart';
import 'tabs/users_tab.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _tabIndex = 0;
  int _pendingCount = 0;
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshNotifications());
    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshNotifications());
  }

  @override
  void dispose() { _notificationTimer?.cancel(); super.dispose(); }

  Future<void> _refreshNotifications() async {
    if (!mounted) return;
    try {
      final response = await context.read<AppProvider>().api.get('${ApiConfig.baseUrl}/notifications/pending');
      if (mounted) setState(() => _pendingCount = response['count'] as int? ?? 0);
    } catch (_) { /* Notification availability never blocks dashboard */ }
  }

  Future<void> _showNotifications() async {
    try {
      final response = await context.read<AppProvider>().api.get('${ApiConfig.baseUrl}/notifications/pending');
      if (!mounted) return;
      final leaves = (response['leaves'] as List?) ?? [];
      final shifts = (response['shifts'] as List?) ?? [];
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Pending approvals'),
        content: SizedBox(width: 450, height: 340, child: ListView(children: [
          if (leaves.isEmpty && shifts.isEmpty) const ListTile(title: Text('No pending requests')),
          for (final item in leaves) ListTile(leading: const Icon(Icons.event_note),
            title: Text('Leave: ${item['employee']}'), subtitle: Text('${item['type']} · ${item['date']}')),
          for (final item in shifts) ListTile(leading: const Icon(Icons.schedule),
            title: Text('Shift: ${item['employee']}'), subtitle: Text('${item['type']} · ${item['date']}')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ));
      await _refreshNotifications();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notifications unavailable: $e'))); }
  }


  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final error = await context.read<AppProvider>().logout();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // AI Assistant is Admin-only now (the backend's ChatController already
    // rejected Auditor calls with a 403 — showing the tab to Auditor anyway
    // just led them to a dead end). Auditor gets Network Settings in that
    // same primary slot instead; Shifts stays Admin-only outright, and
    // Network additionally stays reachable from the drawer for Admin too.
    final role = context.watch<AppProvider>().currentUser?.role ?? '';
    final isAdmin = ['Admin','SuperAdmin','Owner','CountryHead','HeadOfMarketing','HeadOfProcessing'].contains(role);

    final titles = [
      'Today',
      'Attendance',
      'Reports',
      'Team',
      isAdmin ? 'AI Assistant' : 'Network',
      'Analytics',
      'Hours',
      if (isAdmin) 'Shifts',
      if (isAdmin) 'Network',
      'Leave Requests',
    ];
    final navIcons = [
      Icons.today_outlined,
      Icons.event_available_outlined,
      Icons.description_outlined,
      Icons.people_outline,
      isAdmin ? Icons.smart_toy_outlined : Icons.wifi_outlined,
      Icons.insights_outlined,
      Icons.access_time_outlined,
      if (isAdmin) Icons.schedule_outlined,
      if (isAdmin) Icons.wifi_outlined,
      Icons.event_note_outlined,
    ];
    // Network's own position shifts depending on role (Auditor's primary 5th
    // slot vs. Admin's drawer-only last slot) and on whatever else gets added
    // to this list later — 'Network' is always the LAST title appended above,
    // so its index is titles.length - 1 for Admin, or the fixed primary slot
    // (4) for Auditor. Computed here, once, instead of a magic number buried
    // in TodayTab's alert-tile shortcut — that's exactly what silently broke
    // and pointed at Analytics instead of Network the last time a tab (Hours)
    // got inserted before it.
    final networkTabIndex = isAdmin ? titles.length - 2 : 4;
    final tabs = [
      TodayTab(
        onNavigate: (i) => setState(() => _tabIndex = i),
        networkTabIndex: networkTabIndex,
      ),
      const AttendanceTab(),
      const ReportsTab(),
      const TeamTab(),
      if (isAdmin) const AiAssistantView() else const NetworkTab(),
      const AnalyticsTab(),
      const HoursTab(),
      if (isAdmin) const ShiftsTab(),
      if (isAdmin) const NetworkTab(),
      const LeavesTab(),
    ];
    // Analytics (and Network, for Admin) stay reachable from the drawer only
    // — with Team and these, the bottom bar was already six items deep. The
    // 5th slot is AI Assistant for Admin, Network for Auditor;
    // primaryTabCount is how many of `tabs`/`titles` (from the front) get a
    // slot down here, everything past that is drawer-only.
    const primaryTabCount = 5;
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.today_outlined),
        selectedIcon: Icon(Icons.today),
        label: 'Today',
      ),
      const NavigationDestination(
        icon: Icon(Icons.event_available_outlined),
        selectedIcon: Icon(Icons.event_available),
        label: 'Attendance',
      ),
      const NavigationDestination(
        icon: Icon(Icons.description_outlined),
        selectedIcon: Icon(Icons.description),
        label: 'Reports',
      ),
      const NavigationDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: 'Team',
      ),
      isAdmin
          ? const NavigationDestination(
              icon: Icon(Icons.smart_toy_outlined),
              selectedIcon: Icon(Icons.smart_toy),
              label: 'AI Assistant',
            )
          : const NavigationDestination(
              icon: Icon(Icons.wifi_outlined),
              selectedIcon: Icon(Icons.wifi),
              label: 'Network',
            ),
    ];

    if (_tabIndex >= tabs.length) _tabIndex = 0;

    final me = context.watch<AppProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tabIndex]),
        actions: [
          IconButton(
            tooltip: 'Pending approvals: $_pendingCount',
            onPressed: _showNotifications,
            icon: Badge(isLabelVisible: _pendingCount > 0, label: Text('$_pendingCount'),
              child: const Icon(Icons.notifications_outlined)),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                (me?.username.isNotEmpty == true ? me!.username[0] : '?')
                    .toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      me?.fullName.isNotEmpty == true
                          ? me!.fullName
                          : (me?.username ?? ''),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      me?.role ?? '',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'announcements', child: ListTile(leading: Icon(Icons.campaign_outlined), title: Text('Announcements'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded, color: AppColors.danger),
                  title: Text(
                    'Log Out',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'announcements') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen()));
              if (value == 'logout') _handleLogout();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: _AdminDrawer(
        me: me,
        isAdmin: isAdmin,
        titles: titles,
        navIcons: navIcons,
        selectedIndex: _tabIndex,
        onSelectTab: (i) => setState(() => _tabIndex = i),
        onLogout: _handleLogout,
      ),
      body: IndexedStack(index: _tabIndex, children: tabs),
      // Hidden entirely on a drawer-only tab (Analytics/Network) rather than
      // shown with a misleading selectedIndex — there's no slot for those two
      // down here to actually highlight.
      bottomNavigationBar: _tabIndex < primaryTabCount
          ? NavigationBar(
              labelBehavior: MediaQuery.sizeOf(context).width < 380
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              destinations: destinations,
            )
          : null,
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  final AppUser? me;
  final bool isAdmin;
  final List<String> titles;
  final List<IconData> navIcons;
  final int selectedIndex;
  final void Function(int) onSelectTab;
  final VoidCallback onLogout;

  const _AdminDrawer({
    required this.me,
    required this.isAdmin,
    required this.titles,
    required this.navIcons,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final name = me?.fullName.isNotEmpty == true
        ? me!.fullName
        : (me?.username ?? '');
    final initials = (name.isNotEmpty ? name[0] : '?').toUpperCase();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primarySoft,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          me?.role ?? '',
                          style: TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (var i = 0; i < titles.length; i++)
                    ListTile(
                      leading: Icon(
                        navIcons[i],
                        color: i == selectedIndex
                            ? AppColors.primary
                            : AppColors.inkMuted,
                      ),
                      title: Text(
                        titles[i],
                        style: TextStyle(
                          fontWeight: i == selectedIndex
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: i == selectedIndex
                              ? AppColors.primary
                              : AppColors.ink,
                        ),
                      ),
                      selected: i == selectedIndex,
                      selectedTileColor: AppColors.primarySoft,
                      onTap: () {
                        Navigator.of(context).pop();
                        // Allow drawer's route to settle before changing the dependent tab tree.
                        WidgetsBinding.instance.addPostFrameCallback((_) => onSelectTab(i));
                      },
                    ),
                  const Divider(height: 1),
                  if (isAdmin) ListTile(
                    leading: const Icon(Icons.pending_actions_outlined, color: AppColors.inkMuted),
                    title: const Text('Shift Requests'),
                    onTap: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      Future<void>.delayed(Duration.zero, () {
                        nav.push(MaterialPageRoute(builder: (_) => const AdminShiftRequestsScreen()));
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.manage_accounts_outlined,
                      color: AppColors.inkMuted,
                    ),
                    title: const Text('Account Settings'),
                    onTap: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => const ChangeCredentialsScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.danger,
                    ),
                    title: const Text(
                      'Log Out',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onLogout();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
