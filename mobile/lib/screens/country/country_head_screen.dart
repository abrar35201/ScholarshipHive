import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';
import '../announcements/announcements_screen.dart';
import '../account/change_credentials_screen.dart';
import '../shift/shift_request_screen.dart';

/// Organization overview without owner-only security, roles, device or router controls.
class CountryHeadScreen extends StatefulWidget {
  const CountryHeadScreen({super.key});
  @override State<CountryHeadScreen> createState() => _CountryHeadScreenState();
}
class _CountryHeadScreenState extends State<CountryHeadScreen> {
  Map<String,dynamic> _stats = {};
  List<dynamic> _team = [];
  List<dynamic> _visitors = [];
  String? _error;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }
  Future<void> _load() async {
    try {
      final api = context.read<AppProvider>().api;
      final stats = await api.get('${ApiConfig.baseUrl}/admin/dashboard');
      final team = await api.getList('${ApiConfig.baseUrl}/admin/users');
      final visitors = await api.getList('${ApiConfig.baseUrl}/reception/visitors');
      if (mounted) setState(() { _stats = stats; _team = team; _visitors=visitors; _error = null; });
    } catch(e) { if (mounted) setState(() => _error = '$e'); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Country Head · Organization'), actions: [
      IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
        icon: const Icon(Icons.campaign_outlined), tooltip: 'Company announcements'),
      IconButton(onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChangeCredentialsScreen())),
        icon: const Icon(Icons.manage_accounts_outlined), tooltip: 'Password and fingerprint settings'),
      IconButton(onPressed: () => context.read<AppProvider>().logout(), icon: const Icon(Icons.logout)),
    ]),
    body: RefreshIndicator(onRefresh:_load, child: ListView(padding:const EdgeInsets.all(16),children:[
      if(_error != null) Text(_error!,style:const TextStyle(color:Colors.red)),
      Text('Organization-wide live overview',style:Theme.of(context).textTheme.titleLarge),
      OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShiftRequestScreen())), icon: const Icon(Icons.schedule_outlined), label: const Text('My Shift Requests')),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        for(final k in {'Total users':'totalUsers','On the floor':'checkedInNow',
          'Reports today':'reportsToday','Pending approvals':'pendingApprovals',
          'Present on time':'presentOnTimeToday','Absent today':'absentToday'}.entries)
          SizedBox(width:156,child:Card(child:Padding(padding:const EdgeInsets.all(14),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(k.key,style:const TextStyle(fontSize:12)),
              const SizedBox(height:6),
              Text('${_stats[k.value] ?? '–'}',style:Theme.of(context).textTheme.headlineMedium),
            ])))),
      ]),
      const SizedBox(height:22),
      Text('Employee directory (read only)',style:Theme.of(context).textTheme.titleMedium),
      for(final raw in _team) Builder(builder: (context) {
        final u=Map<String,dynamic>.from(raw as Map);
        return Card(child:ListTile(title:Text('${u['fullName'] ?? u['username']}'),
            subtitle:Text('${u['department'] ?? ''} · ${u['role'] ?? ''}')));
      }),
      const SizedBox(height:20),
      Text('Reception visitors (read only)',style:Theme.of(context).textTheme.titleMedium),
      for(final raw in _visitors.take(30)) Builder(builder:(context){
        final visitor=Map<String,dynamic>.from(raw as Map);
        return ListTile(title:Text('${visitor['fullName'] ?? ''}'),subtitle:Text('${visitor['country'] ?? ''} · ${visitor['program'] ?? ''}'));
      }),
      const SizedBox(height:12),
    ])),
  );
}
