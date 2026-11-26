import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'package:fieldforce_hrms/trackyu/local_workspace.dart';
import 'package:fieldforce_hrms/trackyu/visit_reconciliation.dart';
import 'package:fieldforce_hrms/trackyu/visit_overstay_sheet.dart';
import 'session_race_test.dart' show TestVault, TestAdapter, jsonReply;
import 'local_workspace_test.dart' show MemoryWorkspace;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { DutyTracker.platformOverride = false; VisitOverstayAlertSheet.clearSnooze(); });
  TrackyuController make(MemoryWorkspace store,
      Future<ResponseBody> Function(RequestOptions) handle, {bool field = true}) {
    final api = TrackyuApi('https://qa.example/api',
        client: Dio()..httpClientAdapter = TestAdapter(handle),
        deviceIdentity: () async => {'deviceId': 'android:verified-test-phone'});
    api.authorize('session-A');
    return TrackyuController(api, vault: TestVault(), takeSelfie: () async => 'photo',
        locate: () async => {'latitude': 25.0, 'longitude': 75.0,
          'accuracyMeters': 5, 'capturedAtUtc': DateTime.now().toUtc().toIso8601String()})
      ..local = store
      ..user = {'userId': 'SM201'}
      ..isField = field
      ..officeId = field ? null : 1
      ..stateKnown = true;
  }
  Json attendance(String day, {bool closed = false}) => {
    'id': 50, 'workDate': day,
    'punchInUtc': '${day}T04:43:02Z',
    'punchOutUtc': closed ? '${day}T12:00:00Z' : null,
  };
  Json visit(String day, {bool closed = false}) => {
    'id': 437, 'requestId': 'original-start', 'kind': 'Open',
    'shopName': 's b marketing', 'workDate': day,
    'checkInUtc': '${day}T06:22:13Z',
    'checkOutUtc': closed ? '${day}T07:50:57Z' : null,
  };

  for (final field in [true, false]) {
    test('server checkout persists across local reread and restart (${field ? 'field' : 'office'})', () async {
      final store = MemoryWorkspace();
      late TrackyuController c;
      c = make(store, (r) async {
        if (r.path.contains('Attendance/state')) return jsonReply({
          'attendance': attendance(c.localDay), 'activeVisit': null,
          'workDate': c.localDay, 'serverTimeUtc': DateTime.now().toUtc().toIso8601String()});
        if (r.path.startsWith('MobileVisits/mine')) return jsonReply([visit(c.localDay, closed: true)]);
        return jsonReply([]);
      }, field: field);
      addTearDown(c.dispose);
      c.attendance = attendance(c.localDay);
      await store.write(c.dayKey, {'attendance': c.attendance, 'visits': [visit(c.localDay)]});
      await c.readLocal();
      expect(c.activeVisit?['id'], 437);
      await c.refresh();
      await c.readLocal();
      expect(c.activeVisit, isNull);
      expect(visitClosed((await store.read(c.dayKey))!['visits'].single), isTrue);
      final restarted = make(store, (_) async => jsonReply([]), field: field);
      addTearDown(restarted.dispose);
      await restarted.readLocal();
      expect(restarted.activeVisit, isNull);
    });
  }

  test('reachable server overrides stale offline flag; no local confirmed copy before receipt', () async {
    final store = MemoryWorkspace(), sent = Completer<void>(), reply = Completer<ResponseBody>();
    late TrackyuController c;
    c = make(store, (r) async {
      if (r.path == 'FieldAttendance/punch-in') { sent.complete(); return reply.future; }
      return jsonReply({});
    });
    addTearDown(c.dispose);
    c.offline = true;
    final punch = c.punch();
    await sent.future.timeout(const Duration(seconds: 2));
    expect(c.attendance, isNull);
    expect((await store.read(c.dayKey))?['attendance'], isNull);
    expect(store.operations, isEmpty);
    reply.complete(jsonReply(attendance(c.localDay)));
    await punch;
    expect(c.attendance?['id'], 50);
    expect((await store.read(c.dayKey))!['attendance']['id'], 50);
    expect(store.operations, isEmpty);
  });

  test('401 online punch cannot create local attendance or outbox operation', () async {
    final store = MemoryWorkspace();
    final c = make(store, (r) async => r.path.contains('punch-in')
        ? jsonReply(null, status: 401, success: false, code: 'DEVICE_SESSION_INVALID')
        : jsonReply({}));
    addTearDown(c.dispose);
    await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
    expect(c.attendance, isNull);
    expect((await store.read(c.dayKey))?['attendance'], isNull);
    expect(store.operations, isEmpty);
  });

  test('second visit to same shop remains distinct from the first closed visit', () {
    final first = visit('2026-11-24', closed: true);
    final second = {...visit('2026-11-24'), 'id': 438, 'requestId': 'second-start',
      'checkInUtc': '2026-11-24T09:00:00Z'};
    expect(sameVisit(first, second), isFalse);
    expect(mergePendingVisits([first, second], []), hasLength(2));
  });

  test('server commit with lost response is reconciled without creating another punch', () async {
    final store = MemoryWorkspace();
    var writes = 0;
    String? captured;
    late TrackyuController c;
    c = make(store, (r) async {
      if (r.path == 'FieldAttendance/punch-in') {
        writes++; captured = (r.data as Map)['capturedAtUtc'];
        throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
      }
      if (r.path == 'FieldAttendance/state') return jsonReply({
        'attendance': {...attendance(c.localDay), 'punchInUtc': captured},
        'workDate': c.localDay});
      if (r.path.startsWith('MobileVisits/mine')) return jsonReply([]);
      return jsonReply({});
    });
    addTearDown(c.dispose);
    await c.punch();
    expect(writes, 1);
    expect(c.attendance?['id'], 50);
    expect(c.notice, 'Punch-in confirmed by server.');
    expect(store.operations, isEmpty);
  });

  test('incomplete online receipt never creates confirmed attendance', () async {
    final store = MemoryWorkspace();
    final c = make(store, (r) async => r.path.contains('punch-in')
        ? jsonReply({'id': 0}) : jsonReply({}));
    addTearDown(c.dispose);
    await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
    expect(c.attendance, isNull);
    expect((await store.read(c.dayKey))?['attendance'], isNull);
    expect(store.operations, isEmpty);
  });

  test('late server snapshot cannot overwrite a newer local visit', () async {
    final store = MemoryWorkspace(), entered = Completer<void>(), release = Completer<ResponseBody>();
    final c = make(store, (r) async {
      if (r.path == 'FieldAttendance/state') { entered.complete(); return release.future; }
      return jsonReply([]);
    });
    addTearDown(c.dispose);
    c.attendance = attendance(c.localDay);
    await store.write(c.dayKey, {'attendance': c.attendance, 'visits': []});
    final refresh = c.reconcileServerWorkspace();
    await entered.future;
    final newVisit = {...visit(c.localDay), 'id': 999, 'requestId': 'new-start', 'syncState': 'pending'};
    await c.commitLocal({'attendance': c.attendance, 'visits': [newVisit]},
        {'id': 'new-start', 'route': 'MobileVisits/start'});
    release.complete(jsonReply({'attendance': attendance(c.localDay)}));
    expect(await refresh, isFalse);
    expect((await store.read(c.dayKey))!['visits'].single['id'], 999);
    expect(c.activeVisit?['id'], 999);
  });

  testWidgets('visible overstay sheet dismisses immediately when server closure arrives', (tester) async {
    final c = make(MemoryWorkspace(), (_) async => jsonReply({}));
    c.attendance = attendance(c.localDay);
    final row = visit(c.localDay);
    c.activeVisit = row;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => VisitOverstayAlertSheet.show(context: context,
        controller: c, visit: row, elapsedMinutes: 150), child: const Text('show'))))));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.byType(VisitOverstayAlertSheet), findsOneWidget);
    c.markVisitClosedInMemory({...row, 'checkOutUtc': '${c.localDay}T07:50:57Z'});
    await tester.pumpAndSettle();
    expect(find.byType(VisitOverstayAlertSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
