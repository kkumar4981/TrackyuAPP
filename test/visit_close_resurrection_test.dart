import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'session_race_test.dart' show TestVault,TestAdapter,jsonReply;

class FailingQueueVault extends TestVault{
 @override Future<void> writePendingVisits(String? value)async=>throw StateError('QA storage unavailable');
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 TrackyuController make(TestVault vault,Future<ResponseBody> Function(RequestOptions) respond){
  final dio=Dio()..httpClientAdapter=TestAdapter(respond);
  final c=TrackyuController(TrackyuApi('https://test.example/api',client:dio,deviceIdentity:()async=>{'deviceId':'qa'}),vault:vault,locate:()async=>{'latitude':19.0,'longitude':72.0,'accuracyMeters':5.0,'capturedAtUtc':DateTime.now().toUtc().toIso8601String()})..user={'userId':'A'};
  c.api.authorize('qa-session');c.isField=true;c.stateKnown=true;c.enabledMenus={'visits'};c.attendance={'id':1,'punchInUtc':DateTime.now().toUtc().subtract(const Duration(hours:1)).toIso8601String(),'punchOutUtc':null};c.syncServerTime(DateTime.now().toUtc().toIso8601String());return c;
 }
 Json visit(TrackyuController c)=>{'id':268,'kind':'Open','shopName':'Mehta sales','requestId':'start-A','workDate':c.localDay,'checkInUtc':DateTime.now().toUtc().subtract(const Duration(minutes:4)).toIso8601String(),'checkOutUtc':null};
 test('committed server checkout with lost response stays closed after controller recreation and stale snapshots',()async{
  final vault=TestVault();var committed=false,loseResponse=true;
  final c=make(vault,(r)async{
   if(r.path=='MobileMenus')return jsonReply([{'key':'visits','enabled':true}]);
   if(r.path=='MobileVisits/finish'){
    expect(jsonDecode(vault.pendingVisits!).single['body']['departureSelfieBase64'],'saved-photo');
    committed=true;if(loseResponse)throw DioException(requestOptions:r,type:DioExceptionType.connectionError);
    return jsonReply({'id':268,'checkOutUtc':DateTime.now().toUtc().toIso8601String()});
   }return jsonReply([]);
  });
  final row=visit(c);c.activeVisit=row;final data=VisitsData(c,capture:()async=>'saved-photo')..rows=[row];
  expect(await data.save(finish:true,fields:row),isTrue);expect(committed,isTrue);expect(c.activeVisit,isNull);expect(c.pendingVisits,hasLength(1));
  c.setOffline(true);c.dismissClosingVisitBanner();
  expect(c.isVisitClosedOrClosing(row),isTrue);expect(c.activeVisit,isNull);
  data.dispose();c.dispose();
  final restarted=make(vault,(_)async=>jsonReply([]));restarted.setOffline(true);await restarted.scopedVisitCache();restarted.activeVisit=row;
  final restored=VisitsData(restarted);await restored.loadCachedVisits();expect(restored.active,isNull);expect(restarted.activeVisit,isNull);expect(jsonDecode(vault.pendingVisits!).single['body']['departureSelfieBase64'],'saved-photo');
  restarted.pendingVisits.addAll((jsonDecode(vault.pendingVisits!) as List).map((p)=>Map<String,dynamic>.from(p)));restarted.setOffline(false);
  restarted.api.dio.httpClientAdapter=TestAdapter((r)async=>jsonReply({'id':268,'checkOutUtc':DateTime.now().toUtc().toIso8601String()}));await restarted.syncPendingVisits();expect(restarted.pendingVisits,isEmpty);
  restarted.api.dio.httpClientAdapter=TestAdapter((r)async=>r.path=='MobileMenus'?jsonReply([]):jsonReply([row]));await restored.load();expect(restored.active,isNull);expect(restarted.activeVisit,isNull);expect(restored.rows.single['syncState'],'synced');
  restored.dispose();restarted.dispose();loseResponse=false;
 });
 testWidgets('25-second timer cannot restore stale active card while checkout is durably pending',(tester)async{
  final vault=TestVault();final c=make(vault,(_)async=>jsonReply([]));final row=visit(c);c.activeVisit=row;c.setOffline(true);
  final queued={'scope':c.visitCacheScope,'finish':true,'durable':true,'body':{'id':268,'startRequestId':'start-A','requestId':'finish-A','departureSelfieBase64':'saved-photo'}};
  c.pendingVisits.add(queued);vault.pendingVisits=jsonEncode([queued]);vault.cachedVisits=jsonEncode({'scope':c.visitCacheScope,'rows':[row]});
  c.setClosingVisit(id:'268');await tester.pumpWidget(MaterialApp(home:Scaffold(body:SalesmanVisitShortcut(controller:c,enabled:true))));await tester.pump();await tester.pump(const Duration(seconds:26));await tester.pump();
  expect(c.isClosingVisit,isFalse);expect(find.text('VISIT IN PROGRESS'),findsNothing);expect(find.text('Punch Out Visit'),findsNothing);expect(c.activeVisit,isNull);expect(c.pendingVisits.single['body']['departureSelfieBase64'],'saved-photo');
  await tester.pumpWidget(const SizedBox());c.dispose();
 });
 test('closure of one visit does not hide a new visit or another account',()async{
  final c=make(TestVault(),(_)async=>jsonReply([]));final old=visit(c);await c.persistVisitClose(old);
  c.activeVisit={...old,'id':269,'requestId':'start-new'};expect(c.activeVisit?['id'],269);
  c.user={'userId':'B'};c.activeVisit=old;expect(c.activeVisit?['id'],268);c.dispose();
 });
 test('storage failure retains photo in memory and does not fake a completed visit',()async{
  final c=make(FailingQueueVault(),(_)async=>jsonReply([]));c.setOffline(true);final row=visit(c);c.activeVisit=row;final data=VisitsData(c,capture:()async=>'saved-photo')..rows=[row];
  await expectLater(data.save(finish:true,fields:row),throwsStateError);expect(c.pendingVisits.single['body']['departureSelfieBase64'],'saved-photo');expect(c.pendingVisits.single['durable'],isFalse);expect(c.activeVisit?['id'],268);expect(data.active?['id'],268);data.dispose();c.dispose();
 });
 test('cancelled photo capture keeps the genuine active visit',()async{
  final c=make(TestVault(),(_)async=>jsonReply([]));c.setOffline(true);final row=visit(c);c.activeVisit=row;final data=VisitsData(c,capture:()async=>null)..rows=[row];expect(await data.save(finish:true,fields:row),isFalse);expect(c.activeVisit?['id'],268);expect(c.pendingVisits,isEmpty);data.dispose();c.dispose();
 });
}
