import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';

void main(){
 test('goals first request always includes the device identity and bearer',()async{
  final dio=Dio();final seen=<RequestOptions>[];
  final api=TrackyuApi('https://qa.invalid/api',client:dio,deviceIdentity:()async=>{'deviceId':'qa-device'});
  api.authorize('qa-session');
  dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){seen.add(o);h.resolve(Response(requestOptions:o,statusCode:200,data:{'success':true,'data':{'visits':7}}));}));
  final data=await api.monthlyGoals(month:'2026-11');
  expect(data['visits'],7);expect(seen.single.headers['X-Device-ID'],'qa-device');expect(seen.single.headers['Authorization'],'Bearer qa-session');expect(seen.single.uri.queryParameters['month'],'2026-11');
 });
 test('goals authorization failure is propagated with code trace and route',()async{
  final dio=Dio();final api=TrackyuApi('https://qa.invalid/api',client:dio,deviceIdentity:()async=>{'deviceId':'qa-device'});api.authorize('qa-session');
  dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h)=>h.reject(DioException(requestOptions:o,type:DioExceptionType.badResponse,response:Response(requestOptions:o,statusCode:401,data:{'errorCode':'DEVICE_REVOKED','message':'Sign in again','traceId':'qa-trace'})))));
  await expectLater(api.monthlyGoals(),throwsA(isA<ApiFailure>().having((e)=>e.code,'code','DEVICE_REVOKED').having((e)=>e.traceId,'trace','qa-trace').having((e)=>e.route,'route','MobileVisits/goals')));
 });
 test('no goals request before sign-in',()async{
  final api=TrackyuApi('https://qa.invalid/api',deviceIdentity:()async=>throw StateError('Must not request identity before sign-in'));
  expect(await api.monthlyGoals(),isEmpty);
 });
 test('account switch while identity is pending never sends a request for the new account',()async{
  final entered=Completer<void>(),identity=Completer<Json>();final dio=Dio();var sent=0;
  final api=TrackyuApi('https://qa.invalid/api',client:dio,deviceIdentity:(){entered.complete();return identity.future;});api.authorize('user-A');
  dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){sent++;h.resolve(Response(requestOptions:o,statusCode:200,data:{'success':true,'data':{}}));}));
  final pending=api.monthlyGoals();final rejected=expectLater(pending,throwsA(isA<ApiFailure>().having((e)=>e.code,'code','SESSION_CHANGED')));
  await entered.future;api.authorize('user-B');identity.complete({'deviceId':'qa-device'});await rejected;expect(sent,0);
 });
 test('diagnostic metadata excludes payload messages query and invalid trace',(){
  const failure=ApiFailure('DATABASE_ERROR','secret body must not be uploaded',status:500,traceId:'qa-trace',route:'MobileVisits/goals?secret=private');
  expect(failure.diagnosticMetadata,{'code':'DATABASE_ERROR','status':'500','traceId':'qa-trace','route':'MobileVisits/goals'});
  const unsafe=ApiFailure('X','private',traceId:'token=secret&password=bad',route:'MobileVisits/user@example.com');
  expect(unsafe.diagnosticMetadata,{'code':'X'});
 });
}
