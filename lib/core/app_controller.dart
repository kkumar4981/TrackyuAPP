import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import '../services/api.dart';
import '../services/device_health.dart';
import '../services/reminders.dart';
import '../services/store.dart';
import '../services/team_feed.dart';
import '../services/tracking.dart';

const demoMode=bool.fromEnvironment('DEMO',defaultValue:true);
const apiUrl=String.fromEnvironment('API_BASE_URL',defaultValue:'https://oyuapi.in/trackyuapi/api');

class AppController extends ChangeNotifier {
  final api=Api(apiUrl,demoMode),health=DeviceHealth(),feed=TeamFeed();
  final secure=const FlutterSecureStorage();
  final store=LocalStore(demoMode?'demo':'device');
  late Reminders reminders;
  late Tracking tracking;
  late Policy policy;
  bool initialized=false,busy=false,online=false,link=true,simulateOffline=false,syncing=false;
  bool admin=false;
  bool policyLoaded=demoMode;
  String name='Employee',liveStatus='Not connected',lastIssue='';
  Json session={};
  Fix? fix;
  List<Fix> route=[];
  List<TeamMember> team=[];
  List<Json> requests=[],kras=[],reminderRows=[],issues=[],queue=[];
  int pending=0,battery=0;
  int? nativePending;
  DateTime? lastContact;
  Timer? timer;
  StreamSubscription<List<ConnectivityResult>>? networkSubscription;
  StreamSubscription? gpsSubscription;
  bool get checkedIn=>session['active']==true;
  bool get loggedIn=>demoMode || api.token!=null;
  DateTime? get checkInTime=>session['checkedInAt']==null?null:DateTime.parse(session['checkedInAt'] as String);
  String get sessionLabel=>checkedIn?(session['pending']==true?'Checked in · pending verification':'On duty'):'Off duty';
  Future<void> initialize() async {
    if(!demoMode && (!apiUrl.startsWith('https://') || apiUrl.contains('example.invalid'))) {
      throw Exception('Provide a real HTTPS API_BASE_URL for device mode.');
    }
    await store.open();
    final cachedPolicy=await store.get('policy');
    policyLoaded=demoMode || cachedPolicy!=null;
    policy=Policy.parse(cachedPolicy??jsonDecode(await rootBundle.loadString('assets/default_policy.json')));
    session=Map<String,dynamic>.from((await store.get('session')) as Map? ?? {});
    requests=((await store.get('requests')) as List? ?? []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    kras=((await store.get('kras')) as List? ?? []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    route=await store.route(); if(route.isNotEmpty) { fix=route.last; }
    reminders=Reminders(store); await reminders.initialize();
    tracking=Tracking((f)=>unawaited(_acceptFix(f)),(code,message)=>unawaited(report(code,message)));
    if(demoMode) {
      name='Aarav Sharma'; admin=true;
      if(fix==null) { await _acceptFix(Fix(const Uuid().v4(),policy.lat,policy.lng,12,DateTime.now().toUtc())); }
      team=List.generate(8,(i)=>TeamMember('demo-$i',
        ['Aarav Sharma','Neha Verma','Rohan Patel','Sana Khan','Vikram Singh','Priya Das','Amit Jain','Meera Rao'][i],
        i==6?'offDuty':'onDuty',Fix('demo-fix-$i',policy.lat+(i-3)*0.007,
          policy.lng+(i%3-1)*0.011,15,DateTime.now().toUtc().subtract(Duration(minutes:i==5?12:0))),DateTime.now().toUtc()));
      if(kras.isEmpty) { kras=[{'id':'demo-kra','title':'Complete 20 customer visits','target':20,'unit':'visits','progress':8}]; }
    } else {
      api.authorize(await secure.read(key:'fieldforce.accessToken'));
      networkSubscription=Connectivity().onConnectivityChanged.listen((results) {
        final previous=link; link=!results.contains(ConnectivityResult.none);
        if(previous!=link) { unawaited(report(link?'LINK_UP':'LINK_DOWN',link?'Network link available.':'Network link unavailable.')); }
        unawaited(refreshHealth());
      });
      gpsSubscription=GeolocatorBridge.listen(()=>unawaited(refreshHealth()));
    }
    initialized=true;
    if(!demoMode && loggedIn && Platform.isAndroid) { await recoverLostCamera(); }
    await refreshHealth();
    if(loggedIn) { await refreshServer(); }
    await _recoverTracking();
    await refreshLists();
    timer=Timer.periodic(const Duration(seconds:20),(_)=>unawaited(refreshHealth()));
    notifyListeners();
  }
  Future<void> login(String email,String password) async {
    final previousToken=api.token;
    final r=await api.login(email.trim(),password);
    api.authorize(r['accessToken'] as String);
    try {
      final identity=await api.me();
      final oldIdentity=await store.get('accountId');
      if(oldIdentity!=null && oldIdentity!=identity['id']) {
        throw Exception('Sign out and sync the previous account before switching employees.');
      }
      await store.set('accountId',identity['id']);
    } catch(_) { api.authorize(previousToken);rethrow; }
    await secure.write(key:'fieldforce.accessToken',value:api.token);
    await refreshServer(); await refreshHealth(); await _recoverTracking(); notifyListeners();
  }
  Future<void> logout() async {
    if(checkedIn || pending>0 || (nativePending??0)>0) { throw Exception('Check out and sync pending data before logout.'); }
    await tracking.stop(); await feed.close();
    for(final reminder in await reminders.list()) { await reminders.remove(reminder['id'] as int); }
    await store.clearAccount();
    api.authorize(null); await secure.delete(key:'fieldforce.accessToken');
    session={};requests=[];kras=[];route=[];fix=null;issues=[];queue=[];reminderRows=[];
    name='Employee';admin=false;team=[];policyLoaded=false; notifyListeners();
  }
  Future<void> _recoverTracking() async {
    if(demoMode || !loggedIn) { return; }
    if(session['id']==null) { return; }
    try {
      await tracking.configure(policy:policy,baseUrl:apiUrl,token:api.token!,sessionId:session['id'] as String);
      if(!checkedIn) { await tracking.stop();nativePending=await tracking.queued();return; }
      if(health.blockers(policy).isEmpty) { await tracking.start(); }
      else { await report('TRACKING_BLOCKED',health.blockers(policy).join(' ')); }
    } catch(e) { await report('TRACKING_START_FAILED',e.toString()); }
  }
  Future<void> refreshServer() async {
    if(demoMode || !loggedIn || !online) { return; }
    try {
      final me=await api.me(); name=me['name'] as String;
      admin=(me['roles'] as List? ?? []).any((r)=>r=='Admin'||r=='Manager');
      final incoming=await api.policy();
      // Active duty stays on its policy version until checkout.
      if(!checkedIn) { policy=incoming;policyLoaded=true; await store.set('policy',policy.json); }
      kras=await api.kras(); await store.set('kras',kras);
    } catch(e) { await report('PROFILE_SYNC',_error(e)); }
    notifyListeners();
  }
  bool _checking=false;
  Future<void> refreshHealth() async {
    if(_checking || !initialized) { return; } _checking=true;
    try {
      if(!demoMode) {
        await health.inspect(); battery=await Battery().batteryLevel;
        link=!(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);
      }
      final previous=online;
      online=demoMode?!simulateOffline:link && await api.reachable();
      if(previous!=online) { await report(online?'SERVER_REACHABLE':'SERVER_UNREACHABLE',
        online?'Server reachable.':'Server unreachable. Data remains on this device.'); }
      if(online) { lastContact=DateTime.now().toUtc(); }
      if(checkedIn && !demoMode) {
        final blockers=health.blockers(policy);
        if(blockers.isNotEmpty && lastIssue!=blockers.join(' ')) { await report('TRACKING_HEALTH',blockers.join(' ')); }
      }
      if(online && loggedIn) { await sync(); }
      nativePending=demoMode?0:await tracking.queued();
      if(online && loggedIn && !demoMode) {
        try {
          await api.dio.post('/telemetry/heartbeat',data:{'sessionId':session['id'],
            'capturedAt':DateTime.now().toUtc().toIso8601String(),'device':health.toJson(),
            'batteryPercent':battery,'latestFixAt':fix?.capturedAt.toIso8601String()});
        } catch(_) { /* Reachability and heartbeat are separate; no false cause attribution. */ }
      }
      await refreshLists();
    } catch(e) { lastIssue=_error(e); }
    finally { _checking=false; notifyListeners(); }
  }
  Future<void> refreshLists() async {
    pending=await store.count();queue=await store.pending();
    issues=await store.issues();reminderRows=await reminders.list();
  }
  Future<void> report(String code,String message) async {
    lastIssue=message; await store.audit(code,message);
    if(!demoMode && checkedIn) {
      final id=const Uuid().v4();
      await store.enqueue(id,'telemetry/event',{'id':id,'sessionId':session['id'],
        'code':code,'message':message,'capturedAt':DateTime.now().toUtc().toIso8601String()});
    }
    notifyListeners();
  }
  Future<void> _acceptFix(Fix incoming) async {
    await store.addFix(incoming);
    if(fix==null || incoming.capturedAt.isAfter(fix!.capturedAt)) { fix=incoming; }
    route=await store.route();notifyListeners();
  }
  Future<void> refreshFix() async {
    if(demoMode) {
      final f=fix!;
      await _acceptFix(Fix(const Uuid().v4(),f.lat,f.lng,12,DateTime.now().toUtc()));
    } else {
      final f=await tracking.current();
      final problem=policy.fixProblem(f,DateTime.now());
      if(problem!=null) { throw Exception(problem); }
      await _acceptFix(f);
    }
  }
  Future<void> demoMove() async {
    if(!demoMode) { return; }
    final f=fix!;
    await _acceptFix(Fix(const Uuid().v4(),f.lat+0.001,f.lng+0.0003,12,DateTime.now().toUtc()));
  }
  Future<List<Json>> checkAttendance(String event,String reason) async {
    if(!loggedIn) { throw Exception('Sign in first.'); }
    if(event=='checkIn' && checkedIn) { throw Exception('Already checked in.'); }
    if(event=='checkOut' && !checkedIn) { throw Exception('No active duty session.'); }
    if(event=='checkIn') {
      if(!policyLoaded) { throw Exception('Connect to load your assigned attendance policy before the first check-in.'); }
      if(!demoMode) {
        await health.inspect();
        final blockers=health.blockers(policy);
        if(blockers.isNotEmpty) { throw Exception(blockers.join('\n')); }
      }
      await refreshFix();
    }
    final input={'reason':reason};
    return RuleEngine.evaluate(policy,event,policy.facts(DateTime.now(),fix,checkInTime),input);
  }
  Future<void> attendance(String event,String reason) async {
    final violations=await checkAttendance(event,reason);
    if(violations.isNotEmpty) { throw Exception(violations.map((v)=>v['message']).join('\n')); }
    if(!online && !policy.offlineAllowed && event=='checkIn') { throw Exception('This policy requires an online check-in.'); }
    final id=const Uuid().v4();
    final sid=event=='checkIn'?const Uuid().v4():session['id'] as String;
    final now=DateTime.now().toUtc();
    final body={'id':id,'sessionId':sid,'event':event,'reason':reason.trim(),
      'policyId':policy.json['id'],'policyVersion':policy.json['version'],
      'capturedAt':now.toIso8601String(),
      // Never attach stale cached fix to checkout when permission is missing.
      'location':fix!=null && policy.fixProblem(fix!,now)==null?fix!.toJson():null,
      'offlineAtCapture':!online};
    final next={'id':sid,'active':event=='checkIn','pending':true,
      'checkedInAt':event=='checkIn'?now.toIso8601String():session['checkedInAt'],
      'lastEventId':id};
    // Start service while visible. If persistence fails, stop it to avoid orphan tracking.
    if(event=='checkIn' && !demoMode) {
      await tracking.configure(policy:policy,baseUrl:apiUrl,token:api.token!,sessionId:sid);
      await tracking.start();
    }
    try { await store.attendance(id,body,next); session=next; }
    catch(_) { if(event=='checkIn') { await tracking.stop(); } rethrow; }
    if(event=='checkOut') { await tracking.stop(); }
    await refreshLists(); if(online) { await sync(); } notifyListeners();
  }
  Future<void> sync() async {
    if(syncing || !online || !loggedIn) { return; } syncing=true;
    try {
      for(final row in await store.pending()) {
        if((row['nextAt'] as int)>DateTime.now().millisecondsSinceEpoch) { break; }
        final body=Map<String,dynamic>.from(row['payload'] as Map);
        try {
          Json result;
          if(demoMode) { result={'id':row['id'],'accepted':true,'status':'demoSynced'}; }
          else { result=await api.send(row['id'] as String,row['kind'] as String,body,
            bytes:row['kind']=='file'?await store.attachment(body['localPath'] as String):null,
            name:body['name'] as String?); }
          if(result['id']==row['id'] && result['accepted']==false && result['final']==true) {
            if(row['kind']=='attendance') {
              if(result['authoritativeSession'] is! Map) {
                throw Exception('Rejected attendance requires an authoritative session response.');
              }
              // Keep later local punches intact, but stop collecting if a check-in was rejected.
              if(session['lastEventId']==row['id']) {
                session=Map<String,dynamic>.from(result['authoritativeSession'] as Map);
                await store.set('session',session);
                if(!checkedIn) { await tracking.stop(); }
                else { await _recoverTracking(); }
              }
            }
            for(final req in requests.where((e)=>e['id']==row['id'])) {
              req['status']='rejected';req['serverReason']=result['reason'];
            }
            if(row['kind']=='file') {
              requests.insert(0,{...body,'kind':'file','status':'rejected','serverReason':result['reason']});
            }
            await store.audit('SERVER_REJECTED','${row['kind']}: ${result['reason']}');
            lastIssue='Server rejected ${row['kind']}: ${result['reason']}';
            await store.set('requests',requests);
            await store.ack(row['id'] as String);
            // Retain rejected file bytes for user/admin recovery; never silently discard.
            continue;
          }
          if(result['accepted']!=true || result['id']!=row['id']) {
            throw Exception('Server acknowledgement mismatch. Data retained.');
          }
          if(row['kind']=='attendance' && session['lastEventId']==row['id']) {
            session={...session,'pending':false}; await store.set('session',session);
          }
          for(final req in requests.where((e)=>e['id']==row['id'])) {
            req['status']=result['status']??'submitted';
            // Only server-returned approval status is authoritative.
          }
          await store.set('requests',requests);
          await store.ack(row['id'] as String);
          if(row['kind']=='file') {
            final file=File(body['localPath'] as String); if(await file.exists()) { await file.delete(); }
          }
        } catch(e) {
          await store.fail(row,_error(e),permanent:e is DioException &&
            [400,401,403,409,422].contains(e.response?.statusCode));
          await report('SYNC_DEFERRED',_error(e)); break;
        }
      }
    } finally { syncing=false; await refreshLists();notifyListeners(); }
  }
  Future<void> retrySync() async {
    await store.retry();await refreshHealth();
    if(!demoMode && online) { try { await tracking.sync(); } catch(e) { await report('NATIVE_SYNC',_error(e)); } }
  }
  Future<void> request(String kind,Json data) async {
    if(!loggedIn) { throw Exception('Sign in first.'); }
    if(!['leave','intimation','activity','kra/assign'].contains(kind)) { throw Exception('Unsupported operation'); }
    if(kind=='kra/assign' && !admin) { throw Exception('Manager role required.'); }
    final id=const Uuid().v4();
    final body={'id':id,...data,'capturedAt':DateTime.now().toUtc().toIso8601String()};
    await store.enqueue(id,kind,body);
    requests.insert(0,{...body,'kind':kind,'status':'pendingSync'});
    await store.set('requests',requests);await refreshLists();if(online) { await sync(); } notifyListeners();
  }
  Future<void> attachment(bool camera) async {
    late final File input;late final String name;
    if(camera) {
      final permission=await Permission.camera.request();
      if(!permission.isGranted) { throw Exception('Camera permission denied. Open Settings to enable it.'); }
      final photo=await ImagePicker().pickImage(source:ImageSource.camera,imageQuality:80,maxWidth:1920);
      if(photo==null) { return; } input=File(photo.path);name=photo.name;
    } else {
      final selection=await FilePicker.platform.pickFiles(type:FileType.custom,
        allowedExtensions:['pdf','jpg','jpeg','png','docx','xlsx']);
      if(selection==null || selection.files.single.path==null) { return; }
      input=File(selection.files.single.path!);name=selection.files.single.name;
    }
    await queueAttachment(input,name);
  }
  Future<void> queueAttachment(File input,String name) async {
    if(!loggedIn) { throw Exception('Sign in first.'); }
    final encryptedPath=await store.importAttachment(input);
    final id=const Uuid().v4();
    try {
      await store.enqueue(id,'file',{'id':id,'name':p.basename(name),'localPath':encryptedPath,
        'metadata':jsonEncode({'id':id,'sessionId':session['id'],'capturedAt':DateTime.now().toUtc().toIso8601String()})});
    } catch(_) { await File(encryptedPath).delete(); rethrow; }
    await refreshLists();if(online) { await sync(); }notifyListeners();
  }
  Future<void> recoverLostCamera() async {
    final recovered=await ImagePicker().retrieveLostData();
    if(recovered.isEmpty) { return; }
    if(recovered.exception!=null) { await report('CAMERA_RECOVERY',recovered.exception.toString()); }
    for(final file in recovered.files??<XFile>[]) { await queueAttachment(File(file.path),file.name); }
  }
  Future<void> loadTeam() async {
    if(!admin) { throw Exception('Manager/admin role required.'); }
    if(demoMode) { liveStatus='Demo fixtures · not real employees';notifyListeners();return; }
    team=await api.team();
    await feed.connect(apiUrl,() async=>api.token!, (incoming) {
      final i=team.indexWhere((e)=>e.id==incoming.id);
      // Do not let out-of-order events rewind the last known point.
      if(i>=0 && team[i].fix!=null && incoming.fix!=null &&
        incoming.fix!.capturedAt.isBefore(team[i].fix!.capturedAt)) { return; }
      if(i<0) { team.add(incoming); } else { team[i]=incoming; }
      notifyListeners();
    },()=>unawaited(_resnapshot()),(s){liveStatus=s;notifyListeners();});
    notifyListeners();
  }
  Future<void> _resnapshot() async {
    try { team=await api.team();notifyListeners(); }
    catch(e) { liveStatus='Snapshot unavailable: ${_error(e)}';notifyListeners(); }
  }
  Future<void> applyDemoPolicy(Json json) async {
    if(!demoMode) { throw Exception('Production policies must be published by the authorized backend.'); }
    if(checkedIn) { throw Exception('Check out before changing policy.'); }
    policy=Policy(json);await store.set('policy',json);notifyListeners();
  }
  Future<void> resume() async {
    await refreshHealth();
    if(checkedIn && !demoMode) { await _recoverTracking(); }
    await reminders.reconcile();
  }
  String _error(Object e)=>e is DioException?'HTTP ${e.response?.statusCode??'unreachable'}: ${e.response?.data??e.message}':e.toString();
  @override void dispose() {
    timer?.cancel();unawaited(networkSubscription?.cancel());unawaited(gpsSubscription?.cancel());
    unawaited(feed.close());super.dispose();
  }
}

// Isolated wrapper to keep platform event ownership explicit.
class GeolocatorBridge {
  static StreamSubscription listen(void Function() callback)=>
    Geolocator.getServiceStatusStream().listen((_)=>callback());
}
