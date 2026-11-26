import '../trackyu/legacy_map.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_controller.dart';
import '../core/models.dart';

const ink=Color(0xff163039),teal=Color(0xff087f79),amber=Color(0xffad6500);

Future<void> perform(BuildContext context,Future<void> Function() work,{String? success}) async {
  try {
    await work();
    if(context.mounted && success!=null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(success))); }
  } catch(e) {
    if(context.mounted) { await showDialog<void>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Action needs attention'),content:SingleChildScrollView(child:SelectableText('$e')),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('OK'))])); }
  }
}

class LoginScreen extends StatefulWidget {
  final AppController app;
  const LoginScreen(this.app,{super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final email=TextEditingController(),password=TextEditingController();bool loading=false;
  @override void dispose(){email.dispose();password.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:ConstrainedBox(
    constraints:const BoxConstraints(maxWidth:440),child:Padding(padding:const EdgeInsets.all(24),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Icon(Icons.explore_rounded,color:teal,size:64),const SizedBox(height:16),
        const Text('Your work. In sync.',style:TextStyle(fontSize:30,fontWeight:FontWeight.bold,color:ink)),
        const Text("Sign in to your organization's FieldForce account."),const SizedBox(height:24),
        TextField(controller:email,decoration:const InputDecoration(labelText:'Work email'),keyboardType:TextInputType.emailAddress),
        const SizedBox(height:12),TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Password')),
        const SizedBox(height:20),FilledButton(onPressed:loading?null:() async {
          setState(()=>loading=true);await perform(context,()=>widget.app.login(email.text,password.text));
          if(mounted){setState(()=>loading=false);}
        },child:Text(loading?'Signing in...':'Sign in')),
        const SizedBox(height:12),const Text('Location is collected only for the attendance and active-duty features described in your policy.')])))));
}

class AppShell extends StatefulWidget {
  final AppController app;
  const AppShell(this.app,{super.key});
  @override State<AppShell> createState()=>_AppShellState();
}
class _AppShellState extends State<AppShell> {
  int page=0;bool submitting=false;
  AppController get a=>widget.app;
  Future<void> punch() async {
    if(submitting)return;
    final reason=await showDialog<String>(context:context,builder:(_)=>const ReasonDialog());
    if(reason==null || !mounted)return;
    setState(()=>submitting=true);
    await perform(context,()=>a.attendance(a.checkedIn?'checkOut':'checkIn',reason),
      success:'Saved. Check the session and sync status below.');
    if(mounted)setState(()=>submitting=false);
  }
  @override Widget build(BuildContext context) {
    final pages=[home(),MapPage(a),WorkPage(a),FilesPage(a),HealthPage(a)];
    return Scaffold(appBar:AppBar(title:const Row(children:[Icon(Icons.explore_rounded,color:teal),SizedBox(width:8),
      Text('FieldForce',style:TextStyle(fontWeight:FontWeight.w800,color:ink))]),actions:[
        if(demoMode)const Padding(padding:EdgeInsets.all(8),child:Chip(label:Text('DEMO'))),
        IconButton(tooltip:'Sync now',onPressed:()=>perform(context,a.retrySync),icon:const Icon(Icons.sync)),
        if(!demoMode)IconButton(tooltip:'Renew login',onPressed:()=>renewLogin(context,a),icon:const Icon(Icons.lock_reset)),
        if(!demoMode)IconButton(tooltip:'Sign out',onPressed:()=>perform(context,a.logout),icon:const Icon(Icons.logout)),
      ]),body:SafeArea(child:Column(children:[
        Container(width:double.infinity,color:a.online?const Color(0xffe0f3eb):const Color(0xffffedd1),
          padding:const EdgeInsets.symmetric(horizontal:20,vertical:9),child:Row(children:[
            Icon(a.online?Icons.cloud_done_outlined:Icons.cloud_off,size:18,color:a.online?teal:amber),const SizedBox(width:8),
            Expanded(child:Text(a.online?(demoMode?'Demo connection · simulated sync':'Server reachable'):
              'Offline / server unavailable · saving on this device')),
            Text('${a.pending} pending',style:const TextStyle(fontWeight:FontWeight.bold))])),
        if(demoMode)Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:20,vertical:6),
          child:const Text('Sample employees and simulated GPS. Device permissions are not tested in demo mode.',
            style:TextStyle(fontSize:12,color:amber))),
        if(!demoMode && a.health.blockers(a.policy).isNotEmpty)MaterialBanner(
          content:Text(a.health.blockers(a.policy).first),leading:const Icon(Icons.location_off,color:amber),
          actions:[TextButton(onPressed:()=>setState(()=>page=4),child:const Text('Fix setup'))]),
        Expanded(child:pages[page]),
      ])),bottomNavigationBar:NavigationBar(selectedIndex:page,onDestinationSelected:(i){
        setState(()=>page=i);
      },destinations:const [NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Today'),
        NavigationDestination(icon:Icon(Icons.map_outlined),label:'Map'),
        NavigationDestination(icon:Icon(Icons.work_outline),label:'Work'),
        NavigationDestination(icon:Icon(Icons.folder_outlined),label:'Files'),
        NavigationDestination(icon:Icon(Icons.health_and_safety_outlined),label:'Health')]));
  }
  Widget home()=>RefreshIndicator(onRefresh:a.refreshHealth,child:ListView(padding:const EdgeInsets.all(20),children:[
    Text('Hello, ${a.name.split(' ').first}',style:const TextStyle(fontSize:28,fontWeight:FontWeight.w800,color:ink)),
    Text('${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} · ${a.policy.office?'Office':'Field'} employee'),
    const SizedBox(height:20),Container(padding:const EdgeInsets.all(24),decoration:BoxDecoration(
      borderRadius:BorderRadius.circular(24),gradient:const LinearGradient(colors:[Color(0xff123f48),Color(0xff087f79)])),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('ATTENDANCE',style:TextStyle(color:Colors.white70,letterSpacing:2,fontSize:12)),
        const SizedBox(height:12),Text(a.sessionLabel,style:const TextStyle(fontSize:27,fontWeight:FontWeight.bold,color:Colors.white)),
        const SizedBox(height:8),Text(a.checkInTime==null?'Ready when you are.':'Check-in: ${a.checkInTime!.toLocal()}',style:const TextStyle(color:Colors.white70)),
        const SizedBox(height:20),SizedBox(width:double.infinity,child:FilledButton.icon(
          style:FilledButton.styleFrom(backgroundColor:Colors.white,foregroundColor:teal,padding:const EdgeInsets.all(16)),
          onPressed:submitting?null:punch,icon:Icon(a.checkedIn?Icons.logout:Icons.fingerprint),
          label:Text(submitting?'Validating...':a.checkedIn?'End duty / Check out':'Start duty / Check in'))),
        const SizedBox(height:8),const Text('Offline punches remain pending until verified by the server.',style:TextStyle(color:Colors.white70,fontSize:12)),
      ])),const SizedBox(height:16),Wrap(spacing:12,runSpacing:12,children:[
        metric('OFFICE RADIUS','${a.policy.radius.round()} m',Icons.radar),
        metric('MOVEMENT RULE','${a.policy.movement.round()} m',Icons.route),
        metric('DEVICE QUEUE','${a.pending}',Icons.cloud_upload_outlined),
        metric('GPS ACCURACY',a.fix==null?'Unknown':'${a.fix!.accuracy.round()} m',Icons.gps_fixed),
      ]),const SizedBox(height:16),section('Your location',[
        Text(a.fix==null?'No location captured':'${a.fix!.lat.toStringAsFixed(5)}, ${a.fix!.lng.toStringAsFixed(5)}'),
        Text(a.fix==null?'': 'Captured ${age(a.fix!.capturedAt)}'),
        TextButton.icon(onPressed:()=>perform(context,a.refreshFix),icon:const Icon(Icons.my_location),label:const Text('Refresh location')),
      ]),section('Assigned policy',[
        Text(a.policy.label),Text('Shift ${pad(a.policy.n('startHour'))}:${pad(a.policy.n('startMinute'))} - ${pad(a.policy.n('endHour'))}:${pad(a.policy.n('endMinute'))} · grace ${a.policy.n('graceMinutes')} min'),
        const Text('Late arrival and early checkout may require a reason. Server approvals remain authoritative.'),
        if(demoMode)TextButton(onPressed:()=>editPolicy(context,a),child:const Text('Edit demo policy JSON')),
      ]),if(a.lastIssue.isNotEmpty)section('Latest device message',[Text(a.lastIssue)]),
      if(demoMode)section('Try offline and movement',[
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Simulate offline'),value:a.simulateOffline,
          onChanged:(v){a.simulateOffline=v;perform(context,a.refreshHealth);}),
        OutlinedButton.icon(onPressed:()=>perform(context,a.demoMove),icon:const Icon(Icons.directions_walk),label:const Text('Move sample position ~115 m')),
      ]),
  ]));
}

String pad(num v)=>v.toInt().toString().padLeft(2,'0');
String age(DateTime at) {
  final d=DateTime.now().toUtc().difference(at.toUtc());
  if(d.isNegative)return 'timestamp ahead of device clock';
  if(d.inSeconds<60)return '${d.inSeconds}s ago';
  if(d.inMinutes<60)return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}
Widget metric(String label,String value,IconData icon)=>SizedBox(width:156,child:Card(
  color:Colors.white,elevation:0,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Icon(icon,color:teal),const SizedBox(height:12),Text(value,style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:ink)),
    Text(label,style:const TextStyle(fontSize:10,letterSpacing:0.8))]))));
Widget section(String title,List<Widget> children)=>Card(color:Colors.white,elevation:0,margin:const EdgeInsets.only(bottom:14),
  child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:ink)),const SizedBox(height:10),...children])));

class ReasonDialog extends StatefulWidget {
  const ReasonDialog({super.key});
  @override State<ReasonDialog> createState()=>_ReasonDialogState();
}
class _ReasonDialogState extends State<ReasonDialog> {
  final reason=TextEditingController();
  @override void dispose(){reason.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Confirm attendance'),
    content:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('If you are late or leaving early, enter your reason. Applicable policy rules will be checked.'),
      const SizedBox(height:16),TextField(controller:reason,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'Reason, if applicable'))]),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(context,reason.text),child:const Text('Validate & save'))]);
}

class MapPage extends StatefulWidget {
  final AppController a;
  const MapPage(this.a,{super.key});
  @override State<MapPage> createState()=>_MapPageState();
}
class _MapPageState extends State<MapPage> {
  final map=MapController();bool teamMode=false;String query='';TeamMember? selected;
  @override void dispose(){map.dispose();super.dispose();}
  @override Widget build(BuildContext context) {
    final a=widget.a;
    final center=a.fix==null?LatLng(a.policy.lat,a.policy.lng):LatLng(a.fix!.lat,a.fix!.lng);
    final members=a.team.where((m)=>m.name.toLowerCase().contains(query.toLowerCase())).toList();
    return Column(children:[Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      Expanded(child:SegmentedButton<bool>(segments:[const ButtonSegment(value:false,label:Text('My route')),
        if(a.admin)const ButtonSegment(value:true,label:Text('Team map'))],selected:{teamMode},
        onSelectionChanged:(v){setState(()=>teamMode=v.first);if(teamMode)perform(context,a.loadTeam);})),
      IconButton(tooltip:'Center map',onPressed:()=>map.move(selected?.fix==null?center:
        LatLng(selected!.fix!.lat,selected!.fix!.lng),14),icon:const Icon(Icons.my_location)),
    ])),if(teamMode)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextField(
      decoration:const InputDecoration(hintText:'Search employee',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>query=v))),
      Padding(padding:const EdgeInsets.all(8),child:Text(teamMode?
        '${a.liveStatus} · ${members.length} employees':'Last capture: ${a.fix==null?'unavailable':age(a.fix!.capturedAt)}',style:const TextStyle(fontSize:12))),
      Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(18),child:FlutterMap(mapController:map,
        options:MapOptions(initialCenter:center,initialZoom:13),children:[
          legacyMapTiles(offline:()=>!a.online),legacyMapAttribution,
          
          if(!teamMode)CircleLayer(circles:[CircleMarker(point:LatLng(a.policy.lat,a.policy.lng),radius:a.policy.radius,
            useRadiusInMeter:true,color:teal.withValues(alpha:0.08),borderColor:teal,borderStrokeWidth:2),
            if(a.fix!=null)CircleMarker(point:center,radius:a.fix!.accuracy,useRadiusInMeter:true,color:Colors.blue.withValues(alpha:0.12))]),
          if(!teamMode && a.route.length>1)PolylineLayer(polylines:[Polyline(points:a.route.map((f)=>LatLng(f.lat,f.lng)).toList(),strokeWidth:4,color:teal)]),
          MarkerLayer(markers:teamMode?members.where((m)=>m.fix!=null).map((m)=>Marker(point:LatLng(m.fix!.lat,m.fix!.lng),width:52,height:52,
            child:GestureDetector(onTap:()=>setState(()=>selected=m),child:CircleAvatar(backgroundColor:m.status=='offDuty'?Colors.grey:
              m.stale(DateTime.now())?amber:teal,child:Text(m.name.split(' ').map((e)=>e[0]).take(2).join(),style:const TextStyle(color:Colors.white)))))).toList():[
              Marker(point:LatLng(a.policy.lat,a.policy.lng),child:const Icon(Icons.business,color:ink,size:30)),
              if(a.fix!=null)Marker(point:center,child:const Icon(Icons.location_on,color:teal,size:44)),
            ]),
          
        ]))),
      if(teamMode && selected!=null)Padding(padding:const EdgeInsets.all(12),child:section(selected!.name,[
        Text('${selected!.status} · Location ${selected!.fix==null?'unavailable':age(selected!.fix!.capturedAt)}'),
        Text('Last server contact ${selected!.lastContact==null?'unknown':age(selected!.lastContact!)}'),
        if(selected!.stale(DateTime.now()))const Text('Last known position --:-- not a live fix.',style:TextStyle(color:amber)),
      ])),
      const Padding(padding:EdgeInsets.all(10),child:Text('Markers represent received GPS points. Tracking gaps are not filled with invented movement.',style:TextStyle(fontSize:11))),
    ]);
  }
}

class WorkPage extends StatelessWidget {
  final AppController a;
  const WorkPage(this.a,{super.key});
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Work, planned.',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800,color:ink)),const SizedBox(height:16),
    Wrap(spacing:8,runSpacing:8,children:[
      FilledButton.icon(onPressed:()=>requestDialog(context,a,'leave'),icon:const Icon(Icons.event_available),label:const Text('Apply leave')),
      OutlinedButton.icon(onPressed:()=>requestDialog(context,a,'intimation'),icon:const Icon(Icons.schedule),label:const Text('Late intimation')),
      OutlinedButton.icon(onPressed:()=>requestDialog(context,a,'activity'),icon:const Icon(Icons.add_task),label:const Text('Daily activity')),
      if(a.admin)OutlinedButton.icon(onPressed:()=>requestDialog(context,a,'kra/assign'),icon:const Icon(Icons.flag_outlined),label:const Text('Assign KRA')),
    ]),const SizedBox(height:20),section('KRA & progress',[
      if(a.kras.isEmpty)const Text('No assigned KRA available. Pull to refresh after backend setup.'),
      ...a.kras.map((k)=>Padding(padding:const EdgeInsets.only(bottom:14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${k['title']}',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        LinearProgressIndicator(value:(k['target'] is num && (k['target'] as num)>0)?
          ((k['progress'] as num? ?? 0)/(k['target'] as num)).clamp(0.0,1.0):0),
        Text('${k['progress']??0} / ${k['target']} ${k['unit']??''}'),
      ]))),
    ]),section('Requests & daily activity',[
      if(a.requests.isEmpty)const Text('Your saved requests and activities appear here.'),
      ...a.requests.take(30).map((r)=>ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.receipt_long,color:teal),
        title:Text('${r['title']??r['kind']}'),subtitle:Text('${r['date']??r['capturedAt']}\n${r['reason']??r['notes']??''}'),
        trailing:Text('${r['status']}',style:const TextStyle(fontSize:11,color:amber)))),
    ]),section('Daily reminders · India time',[
      const Text('Local reminders also work without internet. Delivery can be affected by device notification settings.'),
      ...a.reminderRows.map((r)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('${r['title']}'),
        subtitle:Text('${pad((r['hour'] as num?) ?? 0)}:${pad((r['minute'] as num?) ?? 0)} · Asia/Kolkata'),
        trailing:IconButton(tooltip:'Delete reminder',icon:const Icon(Icons.delete_outline),onPressed:()=>perform(context,() async {
          await a.reminders.remove(r['id'] as int);await a.refreshHealth();
        })))),
      TextButton.icon(onPressed:()=>reminderDialog(context,a),icon:const Icon(Icons.alarm_add),label:const Text('Add daily reminder')),
    ]),
  ]);
}

Future<void> requestDialog(BuildContext context,AppController a,String kind) async {
  final result=await showDialog<Json>(context:context,builder:(_)=>WorkDialog(kind,a.kras));
  if(result!=null && context.mounted) { await perform(context,()=>a.request(kind,result),success:'Saved. Submission status is shown in Work.'); }
}
class WorkDialog extends StatefulWidget {
  final String kind;final List<Json> kras;
  const WorkDialog(this.kind,this.kras,{super.key});
  @override State<WorkDialog> createState()=>_WorkDialogState();
}
class _WorkDialogState extends State<WorkDialog> {
  final title=TextEditingController(),notes=TextEditingController(),target=TextEditingController(),employee=TextEditingController();
  final form=GlobalKey<FormState>();DateTime date=DateTime.now(),end=DateTime.now();String? kra;
  @override void dispose(){title.dispose();notes.dispose();target.dispose();employee.dispose();super.dispose();}
  String dateText(DateTime d)=>d.toIso8601String().substring(0,10);
  @override Widget build(BuildContext context)=>AlertDialog(title:Text(switch(widget.kind){'leave'=>'Apply leave','intimation'=>'Late pre-intimation','kra/assign'=>'Assign KRA',_=>'Daily activity'}),
    content:SizedBox(width:460,child:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextFormField(controller:title,decoration:const InputDecoration(labelText:'Title'),validator:(v)=>v==null||v.trim().isEmpty?'Required':null),
      const SizedBox(height:12),TextFormField(controller:notes,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'Reason / notes'),
        validator:(v)=>v==null||v.trim().isEmpty?'Required':null),
      ListTile(contentPadding:EdgeInsets.zero,title:Text('Date: ${dateText(date)}'),trailing:const Icon(Icons.calendar_month),onTap:() async {
        final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime.now().subtract(const Duration(days:30)),lastDate:DateTime.now().add(const Duration(days:730)));
        if(d!=null)setState(()=>date=d);
      }),
      if(widget.kind=='leave')ListTile(contentPadding:EdgeInsets.zero,title:Text('To: ${dateText(end)}'),trailing:const Icon(Icons.calendar_month),onTap:() async {
        final d=await showDatePicker(context:context,initialDate:end.isBefore(date)?date:end,firstDate:date,lastDate:DateTime.now().add(const Duration(days:730)));
        if(d!=null)setState(()=>end=d);
      }),
      if(widget.kind=='intimation')ListTile(contentPadding:EdgeInsets.zero,title:Text('Expected arrival: ${target.text.isEmpty?'Choose time':target.text}'),onTap:() async {
        final t=await showTimePicker(context:context,initialTime:TimeOfDay.now());
        if(t!=null)setState(()=>target.text='${pad(t.hour)}:${pad(t.minute)}');
      }),
      if(widget.kind=='activity' && widget.kras.isNotEmpty)DropdownButtonFormField<String>(initialValue:kra,
        decoration:const InputDecoration(labelText:'Related KRA (optional)'),items:[
          const DropdownMenuItem(value:null,child:Text('Other work')),
          ...widget.kras.map((k)=>DropdownMenuItem(value:k['id'] as String,child:Text('${k['title']}',overflow:TextOverflow.ellipsis)))],onChanged:(v)=>setState(()=>kra=v)),
      if(widget.kind=='kra/assign')...[
        TextFormField(controller:employee,decoration:const InputDecoration(labelText:'Employee ID'),validator:(v)=>v==null||v.trim().isEmpty?'Required':null),
        const SizedBox(height:12),TextFormField(controller:target,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Target count'),
          validator:(v)=>(num.tryParse(v??'')??0)<=0?'Enter a positive target':null),
      ],
    ])))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:(){
        if(!form.currentState!.validate())return;
        if(widget.kind=='leave' && end.isBefore(date))return;
        if(widget.kind=='intimation' && target.text.isEmpty)return;
        Navigator.pop(context,<String,dynamic>{'title':title.text.trim(),'reason':notes.text.trim(),'notes':notes.text.trim(),
          'date':dateText(date),if(widget.kind=='leave')'toDate':dateText(end),
          if(widget.kind=='intimation')'expectedArrival':target.text,
          if(widget.kind=='activity')'kraId':kra,
          if(widget.kind=='kra/assign')'employeeId':employee.text.trim(),
          if(widget.kind=='kra/assign')'target':num.parse(target.text),
          if(widget.kind=='kra/assign')'unit':'count',
        });
      },child:const Text('Save request'))]);
}

Future<void> reminderDialog(BuildContext context,AppController a) async {
  final title=await showDialog<String>(context:context,builder:(_)=>const TextEntryDialog('Reminder title'));
  if(title==null || !context.mounted)return;
  final time=await showTimePicker(context:context,initialTime:const TimeOfDay(hour:9,minute:20));
  if(time==null || !context.mounted)return;
  await perform(context,() async { await a.reminders.save(title,time.hour,time.minute);await a.refreshHealth(); },success:'Daily reminder scheduled.');
}
class TextEntryDialog extends StatefulWidget {
  final String title;final bool obscure;
  const TextEntryDialog(this.title,{this.obscure=false,super.key});
  @override State<TextEntryDialog> createState()=>_TextEntryDialogState();
}
class _TextEntryDialogState extends State<TextEntryDialog> {
  final text=TextEditingController();
  @override void dispose(){text.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:Text(widget.title),content:TextField(controller:text,autofocus:true,obscureText:widget.obscure),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(context,text.text),child:const Text('Continue'))]);
}

Future<void> renewLogin(BuildContext context,AppController a) async {
  final email=await showDialog<String>(context:context,builder:(_)=>const TextEntryDialog('Your work email'));
  if(email==null || !context.mounted)return;
  final password=await showDialog<String>(context:context,builder:(_)=>const TextEntryDialog('Password',obscure:true));
  if(password==null || !context.mounted)return;
  await perform(context,()=>a.login(email,password),success:'Login renewed. Tracking credentials updated.');
}

class FilesPage extends StatelessWidget {
  final AppController a;
  const FilesPage(this.a,{super.key});
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Documents & evidence',style:TextStyle(fontSize:27,fontWeight:FontWeight.w800,color:ink)),const SizedBox(height:16),
    section('Capture or upload',[
      const Text('PDF, JPG, PNG, DOCX, XLSX · maximum 10 MB. Queued attachments are encrypted in private app storage.'),const SizedBox(height:16),
      FilledButton.icon(onPressed:()=>perform(context,()=>a.attachment(true),success:'Photo saved to upload queue.'),icon:const Icon(Icons.camera_alt_outlined),label:const Text('Take photo')),
      OutlinedButton.icon(onPressed:()=>perform(context,()=>a.attachment(false),success:'Document saved to upload queue.'),icon:const Icon(Icons.attach_file),label:const Text('Choose document')),
    ]),section('Sync queue',[
      Text('${a.pending} queued operations · native location queue ${a.nativePending??'not initialized'}'),
      ...a.queue.map((q)=>ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.cloud_upload_outlined),
        title:Text('${(q['payload'] as Map)['name']??q['kind']}'),subtitle:Text(q['error']==null?'Waiting for server acknowledgement':'${q['error']}'),
        trailing:Text('Try ${q['attempts']}'))),
      TextButton.icon(onPressed:()=>perform(context,a.retrySync),icon:const Icon(Icons.refresh),label:const Text('Retry sync')),
    ]),section('Save to your phone',[
      const Text('Export a local copy of your recorded route as JSON. Choose the destination using the system file picker.'),
      OutlinedButton(onPressed:()=>perform(context,()=>exportRoute(a)),child:const Text('Save route file')),
    ]),
    if(a.requests.any((r)=>r['kind']=='file' && r['status']=='rejected'))section('Rejected uploads --:-- recover local copy',[
      ...a.requests.where((r)=>r['kind']=='file' && r['status']=='rejected').map((r)=>ListTile(
        contentPadding:EdgeInsets.zero,title:Text('${r['name']}'),subtitle:Text('${r['serverReason']}'),
        trailing:IconButton(tooltip:'Save local copy',icon:const Icon(Icons.save_alt),onPressed:()=>perform(context,() async {
          await FilePicker.platform.saveFile(dialogTitle:'Recover rejected file',fileName:r['name'] as String,
            bytes:Uint8List.fromList(await a.store.attachment(r['localPath'] as String)));
        })))),
    ]),
  ]);
}

Future<void> exportRoute(AppController a) async {
  final bytes=Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert({
    'exportedAt':DateTime.now().toUtc().toIso8601String(),
    'demo':demoMode,'points':a.route.map((f)=>f.toJson()).toList(),
  })));
  await FilePicker.platform.saveFile(dialogTitle:'Save recorded route',
    fileName:'fieldforce-route.json',bytes:bytes,type:FileType.custom,allowedExtensions:['json']);
}

class HealthPage extends StatelessWidget {
  final AppController a;
  const HealthPage(this.a,{super.key});
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Device health',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800,color:ink)),
    const Text('Checks run while the app is active. Native tracking reports supported background events.'),const SizedBox(height:16),
    if(demoMode)section('Demo mode',[const Text('Real permissions and battery status are intentionally not reported as verified. Run DEMO=false on a physical phone.')]),
    section('Connection & tracking',[
      healthRow('API reachability',a.online?'Reachable':'Unreachable',a.online,()=>perform(context,a.refreshHealth)),
      healthRow('GPS / Location services',demoMode?'Not tested':a.health.gps?'On':'Off',!demoMode&&a.health.gps,()=>perform(context,a.health.requestLocation)),
      healthRow('Precise location',demoMode?'Not tested':a.health.precise?'Enabled':'Required',!demoMode&&a.health.precise,()=>perform(context,a.health.requestLocation)),
      healthRow('Background access',demoMode?'Not tested':a.health.background?'Allowed':'Review policy requirements',!demoMode&&a.health.background,()=>perform(context,a.health.requestBackground)),
      Text('Latest GPS: ${a.fix==null?'none':age(a.fix!.capturedAt)}'),
      Text('Battery: ${demoMode?'not tested':'${a.battery}%'}'),
    ]),section('Camera & reminders',[
      healthRow('Camera',demoMode?'Not tested':a.health.camera?'Allowed':'Ask when taking a photo',!demoMode&&a.health.camera,()=>perform(context,() async { await Permission.camera.request();await a.refreshHealth(); })),
      healthRow('Notifications',demoMode?'Not tested':a.health.notifications?'Allowed':'Disabled / not requested',!demoMode&&a.health.notifications,()=>perform(context,() async {await a.reminders.permission();await a.refreshHealth();})),
    ]),section('Battery & vendor settings',[
      Text(demoMode?'Device instructions appear in device mode.':a.health.vendorAdvice),
      if(!demoMode)Text('Battery optimization exemption: ${a.health.batteryExempt==null?'not applicable':a.health.batteryExempt!?'enabled':'not enabled'}'),
      TextButton(onPressed:()=>perform(context,() async {await openAppSettings();}),child:const Text('Open app settings')),
      OutlinedButton(onPressed:()=>perform(context,() async {
        await launchUrl(Uri.parse('https://dontkillmyapp.com/'),mode:LaunchMode.externalApplication);
      }),child:const Text('Manufacturer troubleshooting guide')),
      const Text('Autostart/background switches cannot be verified universally. After setup, run a screen-lock walking test.'),
    ]),section('Recent diagnostics',[
      ...a.issues.map((r)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('${r['code']}',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
        subtitle:Text('${r['message']}\n${r['at']}'))),
    ]),OutlinedButton.icon(onPressed:()=>perform(context,a.refreshHealth),icon:const Icon(Icons.fact_check_outlined),label:const Text('Run checks again')),
  ]);
  Widget healthRow(String label,String status,bool ok,VoidCallback fix)=>ListTile(contentPadding:EdgeInsets.zero,
    leading:Icon(ok?Icons.check_circle_outline:Icons.info_outline,color:ok?teal:amber),title:Text(label),subtitle:Text(status),
    trailing:TextButton(onPressed:demoMode?null:fix,child:const Text('Review')));
}

Future<void> editPolicy(BuildContext context,AppController a) async {
  final result=await showDialog<String>(context:context,builder:(_)=>PolicyDialog(a.policy.json));
  if(result==null || !context.mounted)return;
  await perform(context,()=>a.applyDemoPolicy(Map<String,dynamic>.from(jsonDecode(result) as Map)),success:'Demo policy updated.');
}
class PolicyDialog extends StatefulWidget {
  final Json policy;const PolicyDialog(this.policy,{super.key});
  @override State<PolicyDialog> createState()=>_PolicyDialogState();
}
class _PolicyDialogState extends State<PolicyDialog> {
  late final text=TextEditingController(text:const JsonEncoder.withIndent('  ').convert(widget.policy));
  @override void dispose(){text.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Demo policy · controlled rules'),
    content:SizedBox(width:650,height:440,child:TextField(controller:text,expands:true,maxLines:null,minLines:null,
      style:const TextStyle(fontFamily:'monospace',fontSize:12))),actions:[
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,text.text),child:const Text('Validate & apply'))]);
}

