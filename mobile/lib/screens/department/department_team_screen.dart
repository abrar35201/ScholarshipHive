import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';
import '../announcements/announcements_screen.dart';
import '../account/change_credentials_screen.dart';
import '../shift/shift_request_screen.dart';
import 'department_month_hours_screen.dart';
import '../calling/calling_head_forms_screen.dart';

class DepartmentTeamScreen extends StatefulWidget {
  const DepartmentTeamScreen({super.key});
  @override State<DepartmentTeamScreen> createState() => _DepartmentTeamScreenState();
}
class _DepartmentTeamScreenState extends State<DepartmentTeamScreen> {
  List<dynamic> _users = [];
  Map<String,dynamic> _summary = {};
  String? _error;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  Future<void> _load() async {
    try {
      final api = context.read<AppProvider>().api;
      final rows = await api.getList('${ApiConfig.baseUrl}/team-scope/employees');
      final overview = await api.get('${ApiConfig.baseUrl}/team-scope/summary');
      if (mounted) setState(() { _users = rows; _summary = Map<String,dynamic>.from(overview as Map); _error = null; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  Future<void> _records(int userId) async {
    try {
      final rows=await context.read<AppProvider>().api.getList('${ApiConfig.baseUrl}/team-scope/employees/$userId/records');
      if(!mounted)return;
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Employee attendance & reports'),
        content:SizedBox(width:480,height:380,child:ListView(children:[
          for(final item in rows) ListTile(
            title:Text('${item['date'] ?? ''} · ${item['reportSubmitted']==true ? 'Report filed' : 'No report'}'),
            subtitle:Text('In: ${item['checkInTime'] ?? '-'}\nOut: ${item['checkOutTime'] ?? '-'}\n${item['reportText'] ?? ''}'),
          ),
        ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))]));
    } catch(e){if(mounted)setState(()=>_error='$e');}
  }
  Future<void> _addEmployee() async {
    final name=TextEditingController();final username=TextEditingController();final password=TextEditingController();
    String department = 'Marketing';
    bool passwordHidden = true;
    final marketing = context.read<AppProvider>().currentUser?.role == 'HeadOfMarketing';
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(title:const Text('Add department employee'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Full name')),
        TextField(controller:username,decoration:const InputDecoration(labelText:'Username')),
        TextField(controller:password,obscureText:passwordHidden,decoration:InputDecoration(
          labelText:'Initial password (8+ characters)',
          suffixIcon:IconButton(
            tooltip:passwordHidden ? 'Show password' : 'Hide password',
            icon:Icon(passwordHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed:()=>setDialog(()=>passwordHidden = !passwordHidden),
          ))),
        if(marketing) DropdownButtonFormField<String>(initialValue:department,
          items:const [DropdownMenuItem(value:'Marketing',child:Text('Marketing')),DropdownMenuItem(value:'Interns',child:Text('Interns'))],
          onChanged:(value)=>setDialog(()=>department=value ?? 'Marketing'),
          decoration:const InputDecoration(labelText:'Department')),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Add'))])));
    if(ok==true&&mounted){
      try{await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/team-scope/employees',
        {'fullName':name.text.trim(),'username':username.text.trim(),'password':password.text,if(marketing) 'department': department=='Interns' ? 3 : 4});await _load();}
      catch(e){if(mounted)setState(()=>_error='$e');}
    }
    name.dispose();username.dispose();password.dispose();
  }
  Future<void> _resetDevice(int id, String name) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Reset employee phone?'),
      content: Text('Reset the linked phone for $name? Their next attendance login will require their password and approved office Wi-Fi.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset device'))]));
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/team-scope/employees/$id/reset-device', {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee phone reset.')));
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  Future<void> _removeEmployee(int id) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove employee from team?'),
      content: const Text('The employee will no longer appear on the active roster or be able to sign in. Historical attendance and reports will remain.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))]));
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppProvider>().api.delete('${ApiConfig.baseUrl}/team-scope/employees/$id');
      await _load();
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Department'), actions: [
      IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DepartmentMonthHoursScreen())), icon: const Icon(Icons.schedule), tooltip: 'Monthly department hours'),
      IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShiftRequestScreen())), icon: const Icon(Icons.schedule_outlined), tooltip: 'My Shift Requests'),
      IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
        icon: const Icon(Icons.campaign_outlined), tooltip: 'Announcements'),
      IconButton(onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChangeCredentialsScreen())),
        icon: const Icon(Icons.manage_accounts_outlined), tooltip: 'Password and fingerprint settings'),
      IconButton(onPressed: () => context.read<AppProvider>().logout(), icon: const Icon(Icons.logout)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed:_addEmployee,icon:const Icon(Icons.person_add),label:const Text('Add employee')),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      Text('${_summary['department'] ?? 'My'} Department', style: Theme.of(context).textTheme.headlineSmall),
      if (context.read<AppProvider>().currentUser?.role == 'HeadOfCounselors') Padding(padding: const EdgeInsets.only(top: 12), child: OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallingHeadFormsScreen())), icon: const Icon(Icons.description_outlined), label: const Text('Calling team form records'))),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for(final stat in {'Team members':'employees','Checked in today':'checkedInToday','Present now':'presentNow',
          'Reports today':'reportsToday','Pending leaves':'pendingLeaves','Pending shifts':'pendingShifts'}.entries)
          SizedBox(width: 155, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stat.key, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),Text('${_summary[stat.value] ?? '–'}', style: Theme.of(context).textTheme.headlineMedium)])))),
      ]),
      const SizedBox(height: 18),
      Text('Approved employees in your department', style: Theme.of(context).textTheme.titleMedium),
      if (_users.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No employees yet.')),
      for (final u in _users) Card(child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text('${u['fullName'] ?? u['username']}'),
        subtitle: Text('${u['username']} • ${u['department']}'),
        onTap: () => _records(u['id'] as int),
        trailing: u['isActive'] == true ? PopupMenuButton<String>(
          tooltip: 'Employee actions',
          onSelected: (value) { if (value == 'reset') { _resetDevice(u['id'] as int, '${u['fullName'] ?? u['username']}'); } else if (value == 'remove') { _removeEmployee(u['id'] as int); } },
          itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset phone device')), PopupMenuItem(value: 'remove', child: Text('Remove employee'))]) : const Text('Inactive', style: TextStyle(color: Colors.grey)),
      )),
    ])),
  );
}
