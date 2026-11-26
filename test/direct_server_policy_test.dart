import 'dart:convert';
import 'package:dio/dio.dart';
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
  TrackyuController make({bool outage = false, int receiptId = 70}) {
    final api = TrackyuApi('https://qa.example/api', deviceIdentity: () async => {'deviceId': 'android:server-only-qa'},
      client: Dio()..httpClientAdapter = TestAdapter((r) async {
        if (outage) throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
        if (r.path == 'MobileMenus') return jsonReply([{'key': 'visits', 'enabled': true}]);
        if (r.path == 'MobileVisits/finish') return jsonReply({'id': receiptId, 'checkOutUtc': '2026-11-24T07:50:57Z'});
        if (r.path.startsWith('MobileVisits/mine')) return jsonReply([]);
        return jsonReply({});
      }));
    api.authorize('token');
    final c = TrackyuController(api, vault: TestVault(), takeSelfie: () async => testSelfie,
      locate: () async => {'latitude': 23.1, 'longitude': 77.4, 'accuracyMeters': 5,
        'capturedAtUtc': DateTime.now().toUtc().toIso8601String()})
      ..user = {'userId': 'QA'}..stateKnown = true..isField = true..enabledMenus = {'visits'};
    c.local = MemoryWorkspace(); return c;
  }
  Json active(TrackyuController c) => {'id': 70, 'serverId': 70, 'kind': 'Regular',
    'workDate': c.localDay, 'checkInUtc': '${c.localDay}T04:00:00Z', 'version': 'AAAA'};
  void duty(TrackyuController c) { c.attendance = {'id': 1, 'workDate': c.localDay,
    'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String()}; }

  test('offline attendance and public offline entry cannot create a punch', () async {
    final c = make(outage: true); addTearDown(c.dispose);
    await expectLater(c.punch(), throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'SERVER_REQUIRED')));
    await expectLater(c.recordOfflinePunch(), throwsA(isA<ApiFailure>()));
    expect(c.attendance, isNull); expect(c.pendingPunches, isEmpty);
    expect((c.local as MemoryWorkspace).operations, isEmpty);
  });
  test('logout requesting punch-out fails safely offline and keeps the session', () async {
    final c = make(outage: true); addTearDown(c.dispose); duty(c);
    await expectLater(c.signOut(autoPunchOut: true), throwsA(isA<ApiFailure>()));
    expect(c.loggedIn, isTrue); expect(c.attendance?['punchOutUtc'], isNull);
    expect(c.pendingPunches, isEmpty); expect((c.local as MemoryWorkspace).operations, isEmpty);
  });
  test('legacy attendance remains retained without automatic server replay', () async {
    final c = make(); addTearDown(c.dispose);
    c.pendingPunches.add({'payload': {'selfieBase64': 'old-evidence'}});
    await c.syncPendingPunches();
    expect(c.pendingPunches.single['payload']['selfieBase64'], 'old-evidence');
    expect(c.lastSyncError, contains('review'));
  });
  test('server geofence rejection stays a validation error and cannot invalidate login', () async {
    final c = make(); addTearDown(c.dispose);
    c.api.dio.httpClientAdapter = TestAdapter((r) async => r.path.contains('Attendance/punch-')
        ? jsonReply(null, status: 403, success: false, code: 'OUTSIDE_OFFICE') : jsonReply({}));
    await expectLater(c.punch(), throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'OUTSIDE_OFFICE')));
    expect(c.api.sessionRejected, isFalse);
    expect(c.attendance, isNull);
    expect((c.local as MemoryWorkspace).operations, isEmpty);
  });
  for (final kind in ['Regular', 'REGULAR', 'regular']) {
    test('offline $kind start is rejected without an outbox record', () async {
      final c = make(outage: true); addTearDown(c.dispose); duty(c);
      final data = VisitsData(c, capture: () async => testSelfie); addTearDown(data.dispose);
      await expectLater(data.save(finish: false, fields: {'kind': kind, 'retailerId': 'R1'}), throwsA(isA<ApiFailure>()));
      expect(data.rows, isEmpty); expect((c.local as MemoryWorkspace).operations, isEmpty);
    });
  }
  test('regular checkout cannot bypass policy by omitting kind', () async {
    final c = make(outage: true); addTearDown(c.dispose); duty(c);
    final data = VisitsData(c, capture: () async => testSelfie)..rows = [active(c)]; addTearDown(data.dispose);
    c.activeVisit = active(c);
    await expectLater(data.save(finish: true, fields: {'id': 70}), throwsA(isA<ApiFailure>()));
    expect(data.rows.single['checkOutUtc'], isNull); expect((c.local as MemoryWorkspace).operations, isEmpty);
  });
  test('mismatched checkout receipt cannot close the selected regular visit', () async {
    final c = make(receiptId: 999); addTearDown(c.dispose); duty(c);
    final data = VisitsData(c, capture: () async => testSelfie)..rows = [active(c)]; addTearDown(data.dispose);
    c.activeVisit = active(c);
    await expectLater(data.save(finish: true, fields: {'id': 70}), throwsA(isA<ApiFailure>()));
    expect(data.rows.single['checkOutUtc'], isNull); expect(c.activeVisit?['id'], 70);
    expect((c.local as MemoryWorkspace).operations, isEmpty);
  });
  test('regular checkout uses server timestamp and retains departure selfie after confirmation', () async {
    final c = make(); addTearDown(c.dispose); duty(c);
    final data = VisitsData(c, capture: () async => testSelfie)..rows = [active(c)]; addTearDown(data.dispose);
    c.activeVisit = active(c);
    expect(await data.save(finish: true, fields: {'id': 70}), isTrue);
    expect(data.rows.single['checkOutUtc'], '2026-11-24T07:50:57Z');
    expect(data.rows.single['departureSelfieBase64'], testSelfie);
    expect(c.activeVisit, isNull); expect((c.local as MemoryWorkspace).operations, isEmpty);
  });
  test('generic local commit cannot enqueue attendance or a regular visit', () async {
    final c = make(); addTearDown(c.dispose);
    for (final route in ['FieldAttendance/punch-in', 'OfficeAttendance/punch-out', 'MobileVisits/start']) {
      await expectLater(c.commitLocal({}, {'route': route, 'body': {'kind': 'Regular'}}), throwsA(isA<ApiFailure>()));
    }
    expect((c.local as MemoryWorkspace).operations, isEmpty);
  });
  test('old optimistic regular checkout cannot hide the server active visit', () async {
    late TrackyuController c;
    final api = TrackyuApi('https://qa.example/api', deviceIdentity: () async => {'deviceId': 'android:policy-qa'},
      client: Dio()..httpClientAdapter = TestAdapter((r) async {
        if (r.path == 'FieldAttendance/state') return jsonReply({'attendance': c.attendance, 'workDate': c.localDay});
        if (r.path.startsWith('MobileVisits/mine')) return jsonReply([active(c)]);
        return jsonReply({});
      }));
    api.authorize('token');
    c = TrackyuController(api, vault: TestVault())..user = {'userId': 'QA'}..isField = true..stateKnown = true;
    addTearDown(c.dispose); duty(c);
    final store = MemoryWorkspace(); c.local = store;
    final old = {...active(c), 'checkOutUtc': '${c.localDay}T07:00:00Z', 'syncState': 'pending', 'isOffline': true};
    await store.write(c.dayKey, {'attendance': c.attendance, 'visits': [old]});
    (c.vault as TestVault).cachedVisits = jsonEncode({'scope': c.visitCacheScope, 'rows': [old]});
    c.pendingVisits.add({'scope': c.visitCacheScope, 'finish': true, 'durable': true,
      'body': {'id': 70, 'kind': 'Regular'}});
    await c.reconcileServerWorkspace();
    expect(c.activeVisit?['id'], 70);
    expect(c.activeVisit?['checkOutUtc'], isNull);
    expect((await store.read(c.dayKey))!['legacyRegularVisitsForReview'], hasLength(1));
    expect(c.pendingVisits, hasLength(1));
  });
}
