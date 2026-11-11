import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api_exception.dart';
import '../../../core/app_theme.dart';
import '../../../core/realtime_refresh_mixin.dart';
import '../../../core/validators.dart';
import '../../../models/admin_models.dart';
import '../../../providers/app_provider.dart';
import '../../../widgets/reauth_dialog.dart';
import '../user_detail_screen.dart';

const List<String> _groups = ['Counselors', 'Processing', 'Others', 'Interns', 'Reception', 'Auditors', 'Admins'];
const List<String> _employeeGroups = ['Calling', 'Processing', 'Others', 'Interns', 'Marketing'];

class TeamTab extends StatefulWidget {
  const TeamTab({super.key});

  @override
  State<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<TeamTab> with SingleTickerProviderStateMixin, RealtimeRefreshMixin {
  // Fallback only — live pushes (see RealtimeRefreshMixin) cover the normal case;
  // this just guards against a missed/dropped push.
  static const _autoRefreshInterval = Duration(seconds: 60);

  late final TabController _tabController;
  List<AdminUser>? _users;
  Map<int, TeamMetricsEntry> _metrics = {};
  List<PendingPasswordResetEntry> _passwordResets = [];
  String? _error;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _groups.length, vsync: this);
    _load();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) => _load());
    startListeningForRealtimeChanges();
  }

  @override
  void onRealtimeChanged() => _load();

  @override
  void dispose() {
    _tabController.dispose();
    _autoRefreshTimer?.cancel();
    stopListeningForRealtimeChanges();
    super.dispose();
  }

  List<AdminUser> _usersInGroup(List<AdminUser> approved, String group) {
    switch (group) {
      case 'Reception':
        return approved.where((u) => u.role == 'Receptionist').toList();
      case 'Auditors':
        return approved.where((u) => u.role == 'Auditor').toList();
      case 'Admins':
        return approved.where((u) => (['Admin','Owner','CountryHead','HeadOfMarketing','HeadOfProcessing','HeadOfCounselors'].contains(u.role) || (u.role == 'Employee' && u.department == 'Marketing'))).toList();
      default:
        final dept = group == 'Counselors' ? 'Calling' : group;
        return approved.where((u) => u.role == 'Employee' && u.department == dept).toList();
    }
  }

  Future<void> _load() async {
    final api = context.read<AppProvider>().adminApiService;
    try {
      final users = await api.users();
      if (!mounted) return;
      setState(() {
        _users = users;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }

    // Metrics are a nice-to-have on top of the user list — an older server
    // without this endpoint yet (or any other failure) shouldn't block the
    // list itself from showing.
    try {
      final metrics = await api.teamMetrics();
      if (!mounted) return;
      setState(() => _metrics = {for (final m in metrics) m.userId: m});
    } catch (_) {
      // Leave _metrics as-is; cards just render without the metric rows.
    }

    // Admin only — Auditor gets a 403 from this endpoint, which just means
    // an empty section here rather than a visible error.
    try {
      final resets = await api.passwordResets();
      if (!mounted) return;
      setState(() => _passwordResets = resets);
    } catch (_) {
      if (mounted) setState(() => _passwordResets = []);
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _approve(AdminUser user) async {
    await context.read<AppProvider>().adminApiService.approveUser(user.id);
    await _refresh();
  }

  Future<void> _approvePasswordReset(PendingPasswordResetEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Password Reset'),
        content: Text('Update ${entry.userName}\'s password to what they requested?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await context.read<AppProvider>().adminApiService.approvePasswordReset(entry.id);
    await _refresh();
  }

  Future<void> _rejectPasswordReset(PendingPasswordResetEntry entry) async {
    await context.read<AppProvider>().adminApiService.rejectPasswordReset(entry.id);
    await _refresh();
  }

  Future<void> _delete(AdminUser user) async {
    if (user.username.toLowerCase() == 'admin') return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete "${user.username}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<AppProvider>().adminApiService.deleteUser(user.id);
      await _refresh();
    }
  }

  Future<void> _setMarketingAdmin(AdminUser user) async {
    final grant = user.role == 'Employee';
    try {
      await context.read<AppProvider>().adminApiService.setMarketingAdmin(user.id, grant);
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openForm({AdminUser? existing}) async {
    // Editing an existing user can set a new password for them — re-confirm
    // it's really the admin doing this, not just an unlocked/left-open phone.
    if (existing != null && !await confirmAdminPassword(context)) return;
    if (!mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserFormSheet(existing: existing),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _openDetail(AdminUser user) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserDetailScreen(userId: user.id)),
    );
    await _refresh();
  }

  Widget _buildGroupList(String group) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Builder(
        builder: (context) {
          final users = _users;
          if (users == null) {
            if (_error != null) {
              return ListView(children: [const SizedBox(height: 100), Center(child: Text('Error: $_error'))]);
            }
            return const Center(child: CircularProgressIndicator());
          }

          final approved = users.where((u) => u.isApproved).toList();
          final inGroup = _usersInGroup(approved, group);

          if (inGroup.isEmpty) {
            return ListView(children: const [SizedBox(height: 100), Center(child: Text('No one in this group.'))]);
          }

          final isEmployeeGroup = _employeeGroups.contains(group);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...inGroup.map((u) => isEmployeeGroup
                  ? _TeamMemberCard(
                      user: u,
                      metrics: _metrics[u.id],
                      onTap: () => _openDetail(u),
                      onEdit: () => _openForm(existing: u),
                      onDelete: () => _delete(u),
                    )
                  : _UserTile(
                      user: u,
                      onDelete: () => _delete(u),
                      onTap: () => _openDetail(u),
                      onMarketingAccess: (context.read<AppProvider>().currentUser?.username.toLowerCase() == 'admin' &&
                          u.department == 'Marketing' && (u.role == 'Admin' || u.role == 'HeadOfMarketing' || u.role == 'Employee') && u.username.toLowerCase() != 'admin')
                          ? () => _setMarketingAdmin(u) : null,
                    )),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = (_users ?? []).where((u) => !u.isApproved).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pending Approval (${pending.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...pending.map((u) => _UserTile(
                          user: u,
                          onApprove: () => _approve(u),
                          onDelete: () => _delete(u),
                          onTap: () => _openDetail(u),
                        )),
                  ],
                ),
              ),
            ),
          if (_passwordResets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Password Reset Requests (${_passwordResets.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Submitted from the employee\'s own registered device.', style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
                    const SizedBox(height: 8),
                    ..._passwordResets.map((p) => _PasswordResetTile(
                          entry: p,
                          onApprove: () => _approvePasswordReset(p),
                          onReject: () => _rejectPasswordReset(p),
                        )),
                  ],
                ),
              ),
            ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: [for (final g in _groups) Tab(text: g)],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [for (final g in _groups) _buildGroupList(g)],
            ),
          ),
        ],
      ),
    );
  }
}

String _lastSeenLabel(DateTime lastSeenAt) {
  final minutes = DateTime.now().toUtc().difference(lastSeenAt.toUtc()).inMinutes;
  if (minutes < 1) return 'Last seen just now';
  if (minutes < 60) return 'Last seen ${minutes}m ago';
  final hours = minutes ~/ 60;
  return 'Last seen ${hours}h ${minutes % 60}m ago';
}

/// Comfortably above the normal ~15-30 minute background ping cadence (see
/// StaleAttendanceCheckoutService.StaleThreshold on the backend) — past this,
/// the phone's background monitoring has very likely gone quiet (an OEM
/// battery killer, geofencing that silently died, ...), not just "waiting
/// for its next routine tick". This is the one place an admin can actually
/// see that instead of guessing.
Color _lastSeenColor(DateTime lastSeenAt) {
  final minutes = DateTime.now().toUtc().difference(lastSeenAt.toUtc()).inMinutes;
  return minutes > 40 ? AppColors.danger : AppColors.inkMuted;
}

class _TeamMemberCard extends StatelessWidget {
  final AdminUser user;
  final TeamMetricsEntry? metrics;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TeamMemberCard({required this.user, required this.metrics, required this.onTap, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = user.fullName.isEmpty ? user.username : user.fullName;
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();
    final m = metrics;
    final (bg, fg, label) = switch (m?.status) {
      'OnFloor' => (AppColors.success.withValues(alpha: 0.12), AppColors.success, 'On floor'),
      'CheckedOut' => (AppColors.primarySoft, AppColors.primaryDark, 'Checked out'),
      'Late' => (AppColors.warning.withValues(alpha: 0.12), AppColors.warning, 'Late'),
      _ => (AppColors.danger.withValues(alpha: 0.1), AppColors.danger, 'Absent'),
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primarySoft)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)),
                    alignment: Alignment.center,
                    child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primaryDark)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(user.department, style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
                        if (user.lastSeenAt != null)
                          Text(
                            _lastSeenLabel(user.lastSeenAt!),
                            style: TextStyle(color: _lastSeenColor(user.lastSeenAt!), fontSize: 10.5, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                    child: Text(label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              if (m != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _MiniMetric(label: 'Attendance rate', value: '${m.ratePct}%')),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniMetric(label: 'Reports (30d)', value: '${m.reports}')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Attendance', style: TextStyle(color: AppColors.inkMuted, fontSize: 10.5)),
                    const Spacer(),
                    Text('${m.ratePct}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: m.ratePct / 100,
                    minHeight: 5,
                    backgroundColor: AppColors.primarySoft,
                    valueColor: const AlwaysStoppedAnimation(AppColors.success),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onEdit,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                      child: const Text('Edit', style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDelete,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: AppColors.danger, side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3))),
                      child: const Text('Delete', style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 9.5, color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AdminUser user;
  final VoidCallback? onApprove;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback? onMarketingAccess;

  const _UserTile({required this.user, this.onApprove, required this.onDelete, required this.onTap, this.onMarketingAccess});

  @override
  Widget build(BuildContext context) {
    final name = user.fullName.isEmpty ? user.username : user.fullName;
    final initials = name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primarySoft)),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.primaryDark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      '@${user.username} · ${user.role}${user.role == 'Employee' ? ' · ${user.department}' : ''}',
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (user.isLocked || !user.isActive)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    user.isLocked ? 'Locked' : 'Inactive',
                    style: const TextStyle(color: AppColors.danger, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              if (onApprove != null)
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
                  onPressed: onApprove,
                  tooltip: 'Approve',
                ),
              if (onMarketingAccess != null)
                IconButton(
                  icon: Icon(user.role == 'Admin' ? Icons.admin_panel_settings_outlined : Icons.verified_user_outlined, color: AppColors.primaryDark),
                  onPressed: onMarketingAccess,
                  tooltip: user.role == 'Admin' ? 'Revoke admin access' : 'Grant admin access',
                ),
              if (user.username.toLowerCase() != 'admin')
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordResetTile extends StatelessWidget {
  final PendingPasswordResetEntry entry;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PasswordResetTile({required this.entry, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.deviceRecognized ? Colors.white : AppColors.danger.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: entry.deviceRecognized ? AppColors.primarySoft : AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.userName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text('requested ${entry.requestedAt.toLocal()}'.split('.').first, style: TextStyle(color: AppColors.inkMuted, fontSize: 11.5)),
                if (!entry.deviceRecognized) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Unrecognized device (reinstall/new phone, or not really them) — verify their identity before approving.',
                          style: TextStyle(color: AppColors.danger, fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
            onPressed: onApprove,
            tooltip: 'Approve',
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: AppColors.danger),
            onPressed: onReject,
            tooltip: 'Reject',
          ),
        ],
      ),
    );
  }
}

class UserFormSheet extends StatefulWidget {
  final AdminUser? existing;
  const UserFormSheet({super.key, this.existing});

  @override
  State<UserFormSheet> createState() => UserFormSheetState();
}

class UserFormSheetState extends State<UserFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _fullName;
  final _password = TextEditingController();
  late String _role;
  late String _department;
  late bool _isActive;
  late bool _isApproved;
  bool _busy = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.existing?.username ?? '');
    _fullName = TextEditingController(text: widget.existing?.fullName ?? '');
    _role = widget.existing?.role == 'SuperAdmin' ? 'Admin' : (widget.existing?.role ?? 'Employee');
    _department = widget.existing?.department ?? 'Calling';
    _isActive = widget.existing?.isActive ?? true;
    _isApproved = widget.existing?.isApproved ?? true;
  }

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final api = context.read<AppProvider>().adminApiService;
    try {
      if (widget.existing == null) {
        await api.createUser(
          username: _username.text.trim(),
          fullName: _fullName.text.trim(),
          password: _password.text,
          role: _role,
          department: _department,
        );
      } else {
        await api.editUser(
          id: widget.existing!.id,
          username: _username.text.trim(),
          fullName: _fullName.text.trim(),
          password: _password.text.isEmpty ? null : _password.text,
          role: _role,
          isActive: _isActive,
          isApproved: _isApproved,
          department: _department,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEdit ? 'Edit User' : 'Add User', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: isEdit ? 'New Password (leave blank to keep)' : 'Password',
                helperText: 'At least 8 characters, with upper/lowercase, a number, and a symbol',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: isEdit ? Validators.optionalStrongPassword : Validators.strongPassword,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                if (_role == 'Admin')
                  const DropdownMenuItem(value: 'Admin', child: Text('Admin (protected)')),
                DropdownMenuItem(value: 'Employee', child: Text('Employee')),
                DropdownMenuItem(value: 'Auditor', child: Text('Auditor')),
                DropdownMenuItem(value: 'Receptionist', child: Text('Receptionist')),
                DropdownMenuItem(value: 'Owner', child: Text('Owner')),
                DropdownMenuItem(value: 'CountryHead', child: Text('Country Head')),
                if (context.read<AppProvider>().currentUser?.username.toLowerCase() == 'admin' || _role == 'HeadOfMarketing')
                  const DropdownMenuItem(value: 'HeadOfMarketing', child: Text('Head of Marketing')),
                if (context.read<AppProvider>().currentUser?.username.toLowerCase() == 'admin' || _role == 'HeadOfProcessing')
                  const DropdownMenuItem(value: 'HeadOfProcessing', child: Text('Head of Processing')),
                if (context.read<AppProvider>().currentUser?.username.toLowerCase() == 'admin' || _role == 'HeadOfCounselors')
                  const DropdownMenuItem(value: 'HeadOfCounselors', child: Text('Head of Counselors')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'Employee'),
            ),
            if (_role == 'Employee') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _department,
                decoration: const InputDecoration(labelText: 'Department'),
                items: const [
                  DropdownMenuItem(value: 'Calling', child: Text('Counselors')),
                  DropdownMenuItem(value: 'Processing', child: Text('Processing')),
                  DropdownMenuItem(value: 'Others', child: Text('Others')),
                  DropdownMenuItem(value: 'Interns', child: Text('Interns')),
                  DropdownMenuItem(value: 'Marketing', child: Text('Marketing')),
                ],
                onChanged: (v) => setState(() => _department = v ?? 'Calling'),
              ),
            ],
            if (isEdit) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                title: const Text('Active'),
                onChanged: (v) => setState(() => _isActive = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isApproved,
                title: const Text('Approved'),
                onChanged: (v) => setState(() => _isApproved = v ?? true),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isEdit ? 'Save Changes' : 'Create User'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
