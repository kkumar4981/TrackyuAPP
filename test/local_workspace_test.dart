import 'dart:async';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/local_workspace.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'trackyu_integration_test.dart' show MemoryVault, Adapter, reply;

class MemoryWorkspace extends LocalWorkspace {
  final Map<String, Json> records = {};
  final List<Json> operations = [];
  bool failSave = false;
  int syncs = 0;
  MemoryWorkspace([Json? report]) {
    if (report != null) records['report'] = {'report': report};
  }
  @override
  Future<Json?> read(String key) async =>
      records[key] ?? (key.startsWith('day:') ? records['report'] : null);
  @override
  Future<void> write(String key, Json value) async {
    records[key] = jsonDecode(jsonEncode(value));
  }

  @override
  Future<void> commit(String key, Json value, Json operation) async {
    if (failSave) throw StateError('disk full');
    await write(key, value);
    operations.add(jsonDecode(jsonEncode(operation)));
  }

  @override
  Future<void> sync() async {
    syncs++;
  }

  @override
  Future<Json> syncState() async => {
    'pending': operations.length,
    'blocked': 0,
  };
  @override
  Future<void> offlineTracking(Json value) async {}
}

class WaitingWorkspace extends MemoryWorkspace {
  final gate = Completer<Json?>();
  @override
  Future<Json?> read(String key) => gate.future;
}

class FailingSyncWorkspace extends MemoryWorkspace {
  @override
  Future<void> sync() async {
    throw const ApiFailure('CONNECTION_FAILED', 'Offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TrackyuApi offlineApi() => TrackyuApi('https://test.example/api',
      client: Dio()..httpClientAdapter = Adapter((r) => throw DioException(
          requestOptions: r, type: DioExceptionType.connectionError)),
      deviceIdentity: () async => {'deviceId': 'android:offline-test-device'});
  TrackyuController controller(MemoryWorkspace local) =>
      TrackyuController(
          offlineApi(),
          vault: MemoryVault(),
          locate: () async => {
            'latitude': 23.2,
            'longitude': 77.4,
            'accuracyMeters': 10,
            'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
          },
          takeSelfie: () async => 'photo',
        )
        ..local = local
        ..user = {'userId': 'employee-a'}
        ..stateKnown = true
        ..isField = true
        ..enabledMenus = {'visits'};
  test('offline attendance never commits a local operation', () async {
    final store = MemoryWorkspace(); final c = controller(store);
    await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
    expect(c.attendance, isNull); expect(store.operations, isEmpty); c.dispose();
  });
  test('offline rejection occurs before any local disk transaction', () async {
    final store = MemoryWorkspace()..failSave = true; final c = controller(store);
    await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
    expect(c.attendance, isNull); expect(store.operations, isEmpty); expect(store.syncs, 0); c.dispose();
  });
  test(
    'offline visit finish references server ID and version from start receipt',
    () async {
      final store = MemoryWorkspace();
      final c = controller(store);
      c.attendance = {'id': 77, 'workDate': c.localDay, 'punchInUtc': DateTime.now().toUtc().toIso8601String()};
      c.offline = true;

      final visits = VisitsData(c, capture: () async => 'photo');
      await visits.save(
        finish: false,
        fields: {
          'kind': 'Open',
          'shopName': 'Shop',
          'placeName': 'Place',
          'address': 'Address',
        },
      );
      final start = store.operations.last['id'];
      await visits.save(
        finish: true,
        fields: {
          'id': visits.active!['id'],
          'kind': 'Open',
          'remark': 'Completed',
          'ownerName': 'Owner',
          'mobile': '9999999999',
          'lead': 'Y',
        },
      );
      final finish = store.operations.last;
      expect(finish['refs']['id']['operationId'], start);
      expect(finish['refs']['version']['field'], 'version');
      expect(visits.rows.single['checkOutUtc'], isNotNull);
      expect((await store.read(c.dayKey))!['visits'], hasLength(1));
      visits.dispose();
      c.dispose();
    },
  );
  test(
    'explicit restore saves historical attendance and later reads stay local',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = Adapter((r) {
          calls++;
          if (r.path.endsWith('DutyTracking/day')) {
            final day = (r.data as Map)['date'];
            return reply({
              'recordedPoints': [],
              'events': [],
              'route': {'segments': [], 'stops': []},
              'attendance': [
                {
                  'id': 100,
                  'mode': 'Field',
                  'workDate': day,
                  'punchInUtc': '${day}T04:30:00Z',
                  'punchOutUtc': '${day}T12:30:00Z',
                },
              ],
            });
          }
          if (r.path.contains('MobileVisits/mine')) return reply([]);
          if (r.path.endsWith('Portal/profile')) return reply({'offices': []});
          if (r.path.endsWith('FieldAttendance/state')) {
            return reply({'attendance': null});
          }
          return reply([]);
        });
      final store = MemoryWorkspace();
      final c =
          TrackyuController(
              TrackyuApi('https://test.example/api', client: dio),
              vault: MemoryVault(),
            )
            ..local = store
            ..user = {'userId': 'employee-a'}
            ..isField = true
            ..stateKnown = true;
      expect(await c.restoreDataFromServer(), true);
      final before = calls;
      final today = DateTime.parse(c.localDay);
      final previous = LocalWorkspace.day(
        today.subtract(const Duration(days: 1)),
      );
      final result = await c.workspaceRequest(
        'Portal/attendance',
        body: {'fromDate': previous, 'toDate': previous},
      );
      expect((result as Map)['rows'], hasLength(1));
      expect(calls, before);
      expect(
        store.records.keys.where((k) => k.startsWith('day:')),
        hasLength(7),
      );
      c.dispose();
    },
  );
  test(
    'date range attendance queries server and merges local punches',
    () async {
      int calls = 0;
      final dio = Dio();
      dio.httpClientAdapter = Adapter((r) {
        calls++;
        if (r.path.endsWith('Portal/attendance')) {
          return reply({
            'rows': [
              {
                'id': 101,
                'workDate': '2026-11-20',
                'punchInUtc': '2026-11-20T05:25:00Z',
                'punchOutUtc': '2026-11-20T17:30:00Z',
                'mode': 'Field',
              },
              {
                'id': 100,
                'workDate': '2026-11-19',
                'punchInUtc': '2026-11-19T05:30:00Z',
                'punchOutUtc': '2026-11-19T17:00:00Z',
                'mode': 'Field',
              },
            ],
          });
        }
        return reply([]);
      });
      final store = MemoryWorkspace();
      final c =
          TrackyuController(
              TrackyuApi('https://test.example/api', client: dio),
              vault: MemoryVault(),
            )
            ..local = store
            ..user = {'userId': 'employee-a'}
            ..isField = true
            ..stateKnown = true;

      final result = await c.workspaceRequest(
        'Portal/attendance',
        body: {'fromDate': '2026-11-01', 'toDate': '2026-11-21'},
      );
      expect(calls, 1);
      expect((result as Map)['rows'], hasLength(2));
      c.dispose();
    },
  );
  test('simultaneous offline punch taps cannot enqueue attendance', () async {
    final store = MemoryWorkspace(); final c = controller(store);
    await expectLater(Future.wait([c.punch(), c.punch()]), throwsA(isA<ApiFailure>()));
    expect(store.operations, isEmpty); expect(c.onDuty, isFalse); c.dispose();
  });
  test('network failure never creates a deferred local attendance', () async {
    final store = FailingSyncWorkspace(); final c = controller(store);
    await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
    expect(store.operations, isEmpty); expect(c.attendance, isNull); c.dispose();
  });
  test(
    'a pending local read may complete safely after the controller is disposed',
    () async {
      final store = WaitingWorkspace();
      final c = controller(store);
      final read = c.readLocal();
      c.dispose();
      store.gate.complete({
        'attendance': {'id': 1, 'punchInUtc': '2026-11-09T00:00:00Z'},
      });
      await read;
      expect(c.attendance, isNull);
    },
  );
  test(
    'changing account during GPS capture cannot save to the new account',
    () async {
      final store = MemoryWorkspace();
      final gps = Completer<Json>();
      final c =
          TrackyuController(
              offlineApi(),
              vault: MemoryVault(),
              locate: () => gps.future,
              takeSelfie: () async => 'photo',
            )
            ..local = store
            ..user = {'userId': 'one'}
            ..stateKnown = true
            ..isField = true;
      final save = c.punch();
      await Future<void>.delayed(Duration.zero);
      c.user = {'userId': 'two'};
      gps.complete({
        'latitude': 23.18,
        'longitude': 77.42,
        'accuracyMeters': 10,
        'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
      });
      await expectLater(save, throwsA(isA<ApiFailure>()));
      expect(store.operations, isEmpty);
      c.dispose();
    },
  );
}
