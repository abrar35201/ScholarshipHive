import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/api_config.dart';
class ShiftRequestScreen extends StatefulWidget {
  final String username;
  const ShiftRequestScreen({super.key, this.username = ''});
  @override State<ShiftRequestScreen> createState()=>_ShiftRequestScreenState();
}
class _ShiftRequestScreenState extends State<ShiftRequestScreen> {
  late final _username=TextEditingController(text:widget.username);
  final _password=TextEditingController(); final _reason=TextEditingController();
  final _form=GlobalKey<FormState>();
  TimeOfDay _start=const TimeOfDay(hour:9,minute:30), _end=const TimeOfDay(hour:17,minute:30);
  int _shift=0; bool _busy=false; bool _hidePassword=true; String? _message;
  @override void dispose(){_username.dispose();_password.dispose();_reason.dispose();super.dispose();}
  String _format(TimeOfDay t)=>'${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:00';
  Future<void> _pick(bool start) async {
    final t=await showTimePicker(context:context,initialTime:start?_start:_end);
    if(t!=null)setState((){if(start){_start=t;}else{_end=t;}});
  }
  Future<void> _submit() async {
    if(!_form.currentState!.validate())return;
    setState((){_busy=true;_message=null;});
    try{
      await Dio().post('${ApiConfig.baseUrl}/shift-requests/apply',data:{
        'username':_username.text.trim(),'password':_password.text,
        'shiftType':_shift,'start':_format(_start),'end':_format(_end),'reason':_reason.text.trim(),
      });
      if(mounted)setState(()=>_message='Shift request sent for admin approval.');
    }on DioException catch(e){if(mounted)setState(()=>_message='${e.response?.data ?? e.message}');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Request Custom Shift')),
    body:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Form(key:_form,child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Apply from anywhere — this does not check you in or bypass office Wi-Fi.'),
      TextFormField(controller:_username,decoration:const InputDecoration(labelText:'Username'),
        validator:(v)=>v==null||v.trim().isEmpty?'Required':null),
      TextFormField(controller:_password,obscureText:_hidePassword,
        decoration:InputDecoration(labelText:'Password',suffixIcon:IconButton(
          tooltip:_hidePassword?'Show password':'Hide password',
          icon:Icon(_hidePassword?Icons.visibility_outlined:Icons.visibility_off_outlined),
          onPressed:()=>setState(()=>_hidePassword=!_hidePassword),
        )),
        validator:(v)=>v==null||v.isEmpty?'Required':null),
      DropdownButtonFormField<int>(initialValue:_shift,decoration:const InputDecoration(labelText:'Shift Type'),
        items:const[DropdownMenuItem(value:0,child:Text('Day')),DropdownMenuItem(value:1,child:Text('Night')),
          DropdownMenuItem(value:2,child:Text('Internship'))],onChanged:(v)=>setState(()=>_shift=v??0)),
      Row(children:[Expanded(child:TextButton(onPressed:()=>_pick(true),child:Text('Start ${_format(_start)}'))),
        Expanded(child:TextButton(onPressed:()=>_pick(false),child:Text('End ${_format(_end)}')))]),
      TextFormField(controller:_reason,maxLines:3,decoration:const InputDecoration(labelText:'Reason'),
        validator:(v)=>v==null||v.trim().isEmpty?'Reason required':null),
      const SizedBox(height:16),FilledButton(onPressed:_busy?null:_submit,child:const Text('Send for Approval')),
      if(_message!=null)Text(_message!),
    ]))));
}
