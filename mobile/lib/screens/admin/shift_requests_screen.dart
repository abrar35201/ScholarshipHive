import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_config.dart';
import '../../providers/app_provider.dart';
class AdminShiftRequestsScreen extends StatefulWidget {
  const AdminShiftRequestsScreen({super.key});
  @override State<AdminShiftRequestsScreen> createState() => _AdminShiftRequestsScreenState();
}
class _AdminShiftRequestsScreenState extends State<AdminShiftRequestsScreen> {
  List<dynamic> _items = [];
  String? _message;
  @override void initState(){super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load());}
  Future<void> _load() async {
    try { final result=await context.read<AppProvider>().api.getList('${ApiConfig.baseUrl}/shift-requests/admin');
      if(mounted) setState((){_items=result;_message=null;}); }
    catch(e){if(mounted)setState(() => _message='$e');}
  }
  Future<void> _decision(int id,String result) async {
    try {await context.read<AppProvider>().api.post('${ApiConfig.baseUrl}/shift-requests/admin/$id/decision',{'decision':result});await _load();}
    catch(e){if(mounted)setState(() => _message='$e');}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Shift Requests')),
    body:RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
      if(_message!=null)Text(_message!,style:const TextStyle(color:Colors.red)),
      if(_items.isEmpty)const Text('No requests.'),
      for(final r in _items)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${r['username']} • ${r['status']}',style:Theme.of(context).textTheme.titleMedium),
          Text('Shift: ${r['shiftType']} • ${r['start']} – ${r['end']}'), Text('${r['reason']}'),
          if(r['status']=='Pending')Row(children:[
            TextButton(onPressed:()=>_decision(r['id'] as int,'Approved'),child:const Text('Approve')),
            TextButton(onPressed:()=>_decision(r['id'] as int,'Rejected'),child:const Text('Reject')),
          ])
        ]))),
    ])));
}
