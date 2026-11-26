import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'session_race_test.dart' show TestVault,TestAdapter,jsonReply;

class FailingQueueVault extends TestVault {
  @override Future<void> writePendingVisits(String? value) async => throw StateError('storage unavailable');
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp(()=>DutyTracker.platformOverride=false);
 TrackyuController make(TestVault vault,Future<ResponseBody> Function(RequestOptions) respond){
  final api=TrackyuApi('https://qa.example/api',client:Dio()..httpClientAdapter=TestAdapter(respond),deviceIdentity:()async=>{'deviceId':'qa-old-phone'});
  api.authorize('token-A');return TrackyuController(api,vault:vault)..user={'userId':'A'};
 }
 test('explicit revocation signs out and preserves queued punch, checkout and departure photo',()async{
  final vault=TestVault();final c=make(vault,(_)async=>jsonReply(null,status:401,success:false,code:'DEVICE_SESSION_REVOKED'));addTearDown(c.dispose);
  c.pendingPunches.add({'out':false,'time':'qa-punch','payload':{'requestId':'qa-punch'}});
  c.pendingVisits.add({'scope':c.visitCacheScope,'finish':true,'durable':true,'time':'qa-visit','body':{'id':10,'requestId':'checkout-10','departureSelfieBase64':'photo-retained'}});
  final signedOut=Completer<void>();c.addListener((){if(c.user==null&&!signedOut.isCompleted)signedOut.complete();});
  await expectLater(c.api.request('Employee/my-profile'),throwsA(isA<ApiFailure>()));await signedOut.future.timeout(const Duration(seconds:3));
  expect(c.user,isNull);expect(c.api.authorized,isFalse);expect(vault.value,isNull);
  expect(vault.pendingVisits,contains('photo-retained'));expect(vault.pendingPunches,contains('qa-punch'));
 });
 for(final code in ['UNAUTHORIZED','DEVICE_HEADER_MISSING','AUTH_TOKEN_EXPIRED','DEVICE_SESSION_INVALID'])test('$code does not falsely force device-revocation logout',()async{
  final c=make(TestVault(),(_)async=>jsonReply(null,status:401,success:false,code:code));addTearDown(c.dispose);
  await expectLater(c.api.request('Employee/my-profile'),throwsA(isA<ApiFailure>()));expect(c.user?['userId'],'A');expect(c.api.authorized,isTrue);
 });
 test('delayed revoked response from A cannot sign out current account B',()async{
  final entered=Completer<void>(),release=Completer<ResponseBody>();
  final c=make(TestVault(),(_){entered.complete();return release.future;});addTearDown(c.dispose);
  final request=expectLater(c.api.request('Employee/my-profile'),throwsA(isA<ApiFailure>()));await entered.future;
  c.api.authorize('token-B');c.user={'userId':'B'};release.complete(jsonReply(null,status:401,success:false,code:'DEVICE_SESSION_REVOKED'));await request;
  expect(c.user?['userId'],'B');expect(c.api.authorized,isTrue);
 });
 test('storage failure still locks revoked session without deleting in-memory photo',()async{
  final c=make(FailingQueueVault(),(_)async=>jsonReply(null,status:401,success:false,code:'DEVICE_SESSION_REVOKED'));addTearDown(c.dispose);
  c.pendingVisits.add({'finish':true,'body':{'departureSelfieBase64':'unsaved-photo'}});
  final signedOut=Completer<void>();c.addListener((){if(c.user==null&&!signedOut.isCompleted)signedOut.complete();});
  await expectLater(c.api.request('Employee/my-profile'),throwsA(isA<ApiFailure>()));await signedOut.future.timeout(const Duration(seconds:3));
  expect(c.api.authorized,isFalse);expect(c.pendingVisits.single['body']['departureSelfieBase64'],'unsaved-photo');
 });
 test('account B survives when it signs in during native revocation cleanup',()async{
  DutyTracker.platformOverride=true;
  final entered=Completer<void>(),release=Completer<void>(),finished=Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DutyTracker.channel,(call)async{
    if(call.method=='stop'){if(!entered.isCompleted)entered.complete();await release.future;}return null;
  });
  addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DutyTracker.channel,null));
  final c=make(TestVault(),(_)async=>jsonReply(null,status:401,success:false,code:'DEVICE_SESSION_REVOKED'));addTearDown(c.dispose);
  c.addListener((){if(c.user?['userId']=='B'&&!finished.isCompleted)finished.complete();});
  await expectLater(c.api.request('Employee/my-profile'),throwsA(isA<ApiFailure>()));await entered.future;
  c.api.authorize('token-B');c.user={'userId':'B'};release.complete();await finished.future.timeout(const Duration(seconds:3));
  expect(c.user?['userId'],'B');expect(c.api.authorized,isTrue);
 });
 testWidgets('signed-in app checks session every 30 seconds', (tester)async{
  var calls=0;final c=make(TestVault(),(_)async{calls++;return jsonReply({});});
  await tester.pump(const Duration(seconds:31));await tester.pump();expect(calls,1);c.dispose();
 });
}
