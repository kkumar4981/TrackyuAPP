import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'local_workspace_test.dart' show MemoryWorkspace;
import 'session_race_test.dart' show TestVault, TestAdapter, jsonReply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TrackyuController make(MemoryWorkspace store, Future<ResponseBody> Function(RequestOptions) respond) {
    final client = Dio()..httpClientAdapter = TestAdapter(respond);
    final api = TrackyuApi('https://test.example/api', client: client,
        deviceIdentity: () async => {'deviceId': 'qa'});
    api.authorize('qa-test-token');
    return TrackyuController(api, vault: TestVault(),
      locate: () async => {'latitude': 19.0, 'longitude': 72.0, 'accuracyMeters': 5.0,
        'capturedAtUtc': DateTime.now().toUtc().toIso8601String()}, takeSelfie: () async => 'qa-photo')
      ..local = store ..user = {'userId': 'A'} ..stateKnown = true
      ..isField = true ..enabledMenus = {'visits'};
  }

  test('actual VisitsData load preserves pending checkout/photo and maps server ID', () async {
    final store = MemoryWorkspace();
    final c = make(store, (r) async => jsonReply(r.path == 'MobileMenus'
      ? [{'key':'visits','enabled':true}]
      : [{'id':42,'requestId':'start-A','version':'server','checkOutUtc':null}]));
    await store.write(c.dayKey, {'visits': [
      {'id':9000,'localId':9000,'requestId':'start-A','isOffline':true,'syncState':'pending',
        'checkOutUtc':'local-finished','departureSelfieBase64':'retained-photo'}]});
    final data = VisitsData(c);
    await data.load();
    expect(data.rows, hasLength(1));
    expect(data.rows.single['id'], 42);
    expect(data.rows.single['checkOutUtc'], 'local-finished');
    expect(data.rows.single['departureSelfieBase64'], 'retained-photo');
    expect((await store.read(c.dayKey))!['visits'][0]['localId'], 9000);
    data.dispose(); c.dispose();
  });

  test('actual day refresh retains pending visit and punch data in workspace', () async {
    final store = MemoryWorkspace();
    final c = make(store, (_) async => jsonReply({'visits':[], 'attendance':{'id':42}}));
    await store.write(c.dayKey, {'attendance':{'id':9001,'syncState':'pending','punchOutUtc':'local-out'},
      'visits':[{'id':9000,'isOffline':true,'syncState':'pending','departureSelfieBase64':'saved'}]});
    await c.fetchRouteDayData(c.localDay);
    final saved = (await store.read(c.dayKey))!;
    expect(saved['attendance']['id'], 9001);
    expect(saved['attendance']['punchOutUtc'], 'local-out');
    expect(saved['visits'][0]['departureSelfieBase64'], 'saved');
    c.dispose();
  });

  test('actual day refresh cannot write A response into B workspace', () async {
    final entered = Completer<void>();
    final response = Completer<ResponseBody>();
    final c = make(MemoryWorkspace(), (_) { entered.complete(); return response.future; });
    final request = c.fetchRouteDayData(c.localDay);
    await entered.future;
    final workspaceB = MemoryWorkspace();
    c.user = {'userId':'B'};
    c.local = workspaceB;
    await workspaceB.write(c.dayKey, {'attendance':{'id':555},'visits':[{'id':888}]});
    response.complete(jsonReply({'attendance':{'id':1},'visits':[{'id':2}]}));
    expect(await request, isEmpty);
    expect((await workspaceB.read(c.dayKey))!['attendance']['id'], 555);
    expect((await workspaceB.read(c.dayKey))!['visits'][0]['id'], 888);
    c.dispose();
  });
}
