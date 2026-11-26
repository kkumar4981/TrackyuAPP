import 'package:dio/dio.dart';
import '../core/models.dart';

class Api {
  final Dio dio;
  final bool demo;
  String? token;
  Api(String baseUrl,this.demo):dio=Dio(BaseOptions(baseUrl:baseUrl,
    connectTimeout:const Duration(seconds:8),receiveTimeout:const Duration(seconds:15),
    sendTimeout:const Duration(seconds:30)));
  void authorize(String? value) {
    token=value;
    dio.options.headers['Authorization']=value==null?'':'Bearer $value';
  }
  Future<bool> reachable() async {
    if(demo) { return true; }
    try { final r=await dio.get('/health'); return r.statusCode==200; } catch(_) { return false; }
  }
  Future<Json> login(String email,String password) async => Map<String,dynamic>.from(
    (await dio.post('/auth/login',data:{'email':email,'password':password})).data as Map);
  Future<Json> me() async=>Map<String,dynamic>.from((await dio.get('/me')).data as Map);
  Future<Policy> policy() async=>Policy.parse((await dio.get('/me/policy')).data);
  Future<List<TeamMember>> team() async=>((await dio.get('/team/locations')).data as List)
    .map((e)=>TeamMember.fromJson(Map<String,dynamic>.from(e as Map))).toList();
  Future<List<Json>> kras() async=>((await dio.get('/me/kras')).data as List)
    .map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  Future<Json> send(String id,String kind,Json payload,{List<int>? bytes,String? name}) async {
    final data=kind=='file'?FormData.fromMap({'metadata':payload['metadata'],
      'file':MultipartFile.fromBytes(bytes!,filename:name)}):payload;
    final r=await dio.post('/$kind',data:data,options:Options(headers:{'Idempotency-Key':id},
      validateStatus:(status)=>status!=null && ((status>=200 && status<300)||status==422)));
    return Map<String,dynamic>.from(r.data as Map);
  }
}
