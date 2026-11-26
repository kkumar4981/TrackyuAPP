import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'session_race_test.dart' show TestVault;
void main(){
 test('production controller ignores delayed User A goals after B writes fresh goals',()async{
  final dio=Dio(),entered=Completer<void>();RequestOptions? requestA;RequestInterceptorHandler? handlerA;
  final api=TrackyuApi('https://qa.invalid/api',client:dio,deviceIdentity:()async=>{'deviceId':'qa-device'});
  dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){
   if(o.headers['Authorization']=='Bearer A'){requestA=o;handlerA=h;entered.complete();}
   else{h.resolve(Response(requestOptions:o,statusCode:200,data:{'success':true,'data':{'visits':2}}));}
  }));
  final c=TrackyuController(api,vault:TestVault(),locate:()async=>{},takeSelfie:()async=>'qa');addTearDown(c.dispose);
  c.user={'userId':'A'};api.authorize('A');final delayed=c.refreshGoals();await entered.future;
  c.user={'userId':'B'};api.authorize('B');expect(c.monthlyGoals,isNull);await c.refreshGoals();expect(c.monthlyGoals?['visits'],2);
  handlerA!.resolve(Response(requestOptions:requestA!,statusCode:200,data:{'success':true,'data':{'visits':999}}));await delayed;
  expect(c.monthlyGoals?['visits'],2);expect(c.loadingGoals,isFalse);
  c.user=null;api.authorize(null);expect(c.monthlyGoals,isNull);
 });
}
