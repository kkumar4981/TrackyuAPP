import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'local_workspace_test.dart' show MemoryWorkspace;
import 'session_race_test.dart' show TestVault, TestAdapter, jsonReply;
import 'trackyu_integration_test.dart' show testSelfie;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => DutyTracker.platformOverride = false);
  TrackyuController session(Future<ResponseBody> Function(RequestOptions) handle) {
    final api = TrackyuApi('https://qa.example/api',
      client: Dio()..httpClientAdapter = TestAdapter(handle),
      deviceIdentity: () async => {'deviceId': 'android:regular-visit-qa'});
    api.authorize('qa-token');
    final c = TrackyuController(api, vault: TestVault(), locate: () async => {
      'latitude': 23.1617, 'longitude': 77.4258, 'accuracyMeters': 5,
      'textLocation': 'Kolar Road, Bhopal', 'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
    })..user = {'userId': 'IN015'}..isField = true..stateKnown = true..enabledMenus = {'visits'};
    c.attendance = {'id': 1, 'workDate': c.localDay,
      'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String()};
    return c;
  }

  test('regular start server rejection cannot create a local completed visit or retry loop', () async {
    var starts = 0;
    final c = session((r) async {
      if (r.path == 'MobileMenus') return jsonReply([{'key': 'visits', 'enabled': true}]);
      if (r.path == 'MobileVisits/start') {
        starts++;
        return jsonReply(null, status: 409, success: false, code: 'RETAILER_LOCATION_MISSING');
      }
      return jsonReply([]);
    });
    addTearDown(c.dispose);
    final store = MemoryWorkspace(); c.local = store;
    final data = VisitsData(c, capture: () async => testSelfie); addTearDown(data.dispose);
    await expectLater(data.save(finish: false, fields: {
      'kind': 'Regular', 'retailerId': 'QI1502', 'shopName': 'Unmapped shop', 'address': 'Bhopal',
    }), throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'RETAILER_LOCATION_MISSING')));
    expect(starts, 1);
    expect(store.operations, isEmpty);
    expect(data.rows, isEmpty);
    expect((await store.read(c.dayKey))?['visits'], isNull);
  });

  test('regular online start waits for receipt before saving local copy', () async {
    final entered = Completer<void>(), response = Completer<ResponseBody>();
    Json? row;
    final c = session((r) async {
      if (r.path == 'MobileMenus') return jsonReply([{'key': 'visits', 'enabled': true}]);
      if (r.path == 'MobileVisits/start') {
        expect((r.data as Map)['photoBase64'], testSelfie);
        row = {...Map<String, dynamic>.from(r.data as Map), 'id': 700, 'version': 'AAAA', 'checkOutUtc': null};
        entered.complete(); return response.future;
      }
      if (r.path.startsWith('MobileVisits/mine')) return jsonReply(row == null ? [] : [row]);
      return jsonReply({});
    });
    addTearDown(c.dispose);
    final store = MemoryWorkspace(); c.local = store;
    final data = VisitsData(c, capture: () async => testSelfie); addTearDown(data.dispose);
    final save = data.save(finish: false, fields: {'kind': 'Regular', 'retailerId': 'QI1501', 'address': 'Bhopal'});
    await entered.future;
    expect(data.rows, isEmpty);
    expect(store.operations, isEmpty);
    expect((await store.read(c.dayKey))?['visits'], isNull);
    response.complete(jsonReply({'id': 700, 'version': 'AAAA'}));
    expect(await save, isTrue);
    expect((await store.read(c.dayKey))!['visits'].single['id'], 700);
    expect(store.operations, isEmpty);
  });

  test('offline regular checkout is rejected before photo capture or local queue', () async {
    final c = session((r) async => throw DioException(requestOptions: r, type: DioExceptionType.connectionError));
    addTearDown(c.dispose); c.offline = true;
    final store = MemoryWorkspace(); c.local = store;
    var captures = 0;
    final data = VisitsData(c, capture: () async { captures++; return testSelfie; });
    addTearDown(data.dispose);
    final row = {'id': 700, 'serverId': 700, 'kind': 'Regular', 'shopName': 'QA shop',
      'workDate': c.localDay, 'checkInUtc': DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String(),
      'version': 'AAAA'};
    data.rows = [row]; c.activeVisit = row;
    await expectLater(data.save(finish: true, fields: row), throwsA(isA<ApiFailure>()));
    expect(captures, 0);
    expect(store.operations, isEmpty);
    expect(data.rows.single['checkOutUtc'], isNull);
  });

  testWidgets('distant retailer action stays within small screen at large text', (tester) async {
    tester.view.physicalSize = const Size(360, 840); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final c = session((r) async => r.path.startsWith('MobileVisits/retailers') ? jsonReply([
      {'id': 'QI1501', 'name': 'QA TEST IN015 Retailer 01', 'address': 'Temporary QA retailer',
        'latitude': 37.4219983, 'longitude': -122.084},
    ]) : jsonReply([]));
    final data = VisitsData(c);
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.4)), child: child!),
      home: SelectRegularPartyPage(data: data)));
    await tester.pumpAndSettle();
    final action = find.ancestor(of: find.textContaining(RegExp(r'Punch In|Start Visit')), matching: find.byType(ElevatedButton));
    expect(action, findsOneWidget);
    expect(tester.getRect(action).right, lessThanOrEqualTo(360));
    expect(tester.getRect(action).left, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    data.dispose(); c.dispose();
  });
}
