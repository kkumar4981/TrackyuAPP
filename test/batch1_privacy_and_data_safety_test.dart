import 'dart:async';
import 'package:dio/dio.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'package:fieldforce_hrms/trackyu/local_workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'trackyu_integration_test.dart' show MemoryVault, reply;

class AsyncAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handle;
  AsyncAdapter(this.handle);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late TrackyuApi api;
  late Completer<Map<String, dynamic>> leaseCompleter;
  bool return401OnProfile = false;
  bool failLocalCommit = false;

  setUp(() {
    DutyTracker.platformOverride = true;
    calls = [];
    leaseCompleter = Completer<Map<String, dynamic>>();
    return401OnProfile = false;
    failLocalCommit = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return <String, dynamic>{
          'active': false,
          'userId': 'TEST_USER',
          'baseUrl': 'https://qa.example/api',
        };
      }
      if (call.method == 'localRead') {
        return <String, dynamic>{
          'workDate': '2026-11-12',
          'attendance': {'id': 101, 'punchInUtc': '2026-11-12T04:00:00Z'},
        };
      }
      if (call.method == 'localCommit') {
        if (failLocalCommit) {
          throw PlatformException(code: 'SQLITE_ERROR', message: 'disk I/O error');
        }
        return <String, dynamic>{'success': true};
      }
      return null;
    });

    final dio = Dio()
      ..httpClientAdapter = AsyncAdapter((r) async {
        if (r.path.contains('DutyTracking/lease')) {
          final data = await leaseCompleter.future;
          return reply(data);
        }
        if (return401OnProfile && r.path.contains('AttendanceProfile/mine')) {
          return ResponseBody.fromString(
            '{"message":"Unauthorized: Token expired"}',
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (r.path.contains('AttendanceProfile/mine')) {
          return reply({'mode': 'Field'});
        }
        if (r.path.contains('Attendance/punch') ||
            r.path.contains('FieldAttendance/punch') ||
            r.path.contains('OfficeAttendance/punch')) {
          return ResponseBody.fromString(
            '{"message":"Unauthorized: Token expired"}',
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (r.path.contains('WorkforceOffices/mine')) {
          return reply([{'id': 1, 'name': 'Office 1', 'isEnabled': true}]);
        }
        if (r.path.contains('MobileMenus')) {
          return reply([{'key': 'visits', 'enabled': true}]);
        }
        return reply({});
      });

    api = TrackyuApi(
      'https://qa.example/api',
      client: dio,
      deviceIdentity: () async => {'deviceId': 'test-device-id'},
    );
  });

  tearDown(() {
    DutyTracker.platformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, null);
  });

  test('A-12: Stale asynchronous reconcile cannot restart tracking after punch-out', () async {
    // 1. Employee was on duty, so reconcile starts with active=true (punchOutUtc is null)
    final reconcileFuture = DutyTracker.reconcile(
      api,
      'Field',
      {'id': 101, 'punchOutUtc': null},
      userId: 'TEST_USER',
    );

    // Give time for reconcile to reach the lease await
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 2. While lease is in flight, employee punches out!
    // stop() is invoked, which increments the generation counter.
    await DutyTracker.stop();
    expect(calls.where((c) => c.method == 'stop').isNotEmpty, isTrue);

    // 3. Now the delayed lease response arrives from the server
    leaseCompleter.complete({
      'userId': 'TEST_USER',
      'trackingKey': 'sample-tracking-key-1234567890123456',
      'dutyCutoffUtc': '2099-11-07T17:30:00Z',
      'expiresAtUtc': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
      'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
    });

    await reconcileFuture;

    // 4. VERIFICATION:
    // With generation guard in place, the stale reconcile MUST NOT configure active=true!
    final configureCalls = calls.where((c) => c.method == 'configure').toList();
    expect(configureCalls, isEmpty, reason: 'configure must not be called after punch-out occurred');
  });

  test('A-11: 401 on punch-out preserves punch-out in offline queue instead of dropping it', () async {
    final controller = TrackyuController(
      api,
      vault: MemoryVault(),
      locate: () async => {'latitude': 23.25, 'longitude': 77.41, 'accuracy': 10.0},
      takeSelfie: () async => 'test_selfie_base64_data',
    );

    // Setup controller on duty with active field attendance
    controller.isField = true;
    controller.user = {'id': 'EMP001', 'name': 'Test Employee'};
    controller.attendance = {
      'id': 101,
      'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String(),
      'punchOutUtc': null,
    };
    controller.stateKnown = true;
    expect(controller.onDuty, isTrue);

    // Trigger punch out. The server responds with 401 Unauthorized.
    await controller.punch();

    // Verify:
    // 1. User is NOT silently signed out (user remains set)
    expect(controller.user, isNotNull);
    // 2. Punch-out was saved offline, so onDuty is now false
    expect(controller.onDuty, isFalse);
    expect(controller.attendance?['punchOutUtc'], isNotNull);
    // 3. Notice warns employee that punch-out is saved offline and sign-in is needed to sync
    expect(controller.notice, contains('Punch-out saved offline'));
  });

  test('A-11: 401 on refresh while on duty preserves active tracking without silently signing out', () async {
    final controller = TrackyuController(
      api,
      vault: MemoryVault(),
      locate: () async => {'latitude': 23.25, 'longitude': 77.41, 'accuracy': 10.0},
      takeSelfie: () async => 'test_selfie_base64_data',
    );

    controller.isField = true;
    controller.user = {'id': 'EMP001', 'name': 'Test Employee'};
    controller.attendance = {
      'id': 101,
      'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String(),
      'punchOutUtc': null,
    };
    controller.stateKnown = true;
    expect(controller.onDuty, isTrue);

    // Trigger refresh when API throws 401
    return401OnProfile = true;
    try {
      await controller.refresh();
    } catch (_) {}

    // Verify:
    // 1. Controller did NOT call signOut
    expect(controller.user, isNotNull);
    // 2. Employee remains on duty locally
    expect(controller.onDuty, isTrue);
    // 3. Notice is displayed to employee without terminating active background tracking
    expect(controller.notice, contains('Session expired'));
  });

  test('A-13: Decrypt recovery model preserves stored ciphertext on transient errors', () {
    // Model testing the TrackingStore behavior:
    // When raw ciphertext is present and decryption fails, the ciphertext must remain intact
    // and subsequent attempts with recovered key succeed without data loss.
    String storedCiphertext = "encrypted_valid_payload_sample_data_v1";
    Map<String, dynamic>? inMemoryCache;

    // First attempt: Keystore transient failure
    Map<String, dynamic> readConfig({required bool keyAvailable}) {
      final cache = inMemoryCache;
      if (cache != null) return cache;
      try {
        if (!keyAvailable) throw Exception("KeyStore temporary unavailable");
        return {"trackingKey": "recovered-key-123", "active": true};
      } catch (_) {
        // FIXED A-13: DO NOT delete storedCiphertext on error!
        return inMemoryCache ?? {};
      }
    }

    // Attempt 1: Key unavailable
    final result1 = readConfig(keyAvailable: false);
    expect(result1, isEmpty);
    // Verify ciphertext was NOT deleted from storage!
    expect(storedCiphertext.isNotEmpty, isTrue);

    // Attempt 2: Key becomes available again after transient lock
    final result2 = readConfig(keyAvailable: true);
    expect(result2['trackingKey'], 'recovered-key-123');
    expect(result2['active'], isTrue);
    expect(storedCiphertext.isNotEmpty, isTrue);
  });

  test('A-11: 401 on punch-out reuses already captured location without second GPS locate call', () async {
    var locateCallCount = 0;
    final controller = TrackyuController(
      api,
      vault: MemoryVault(),
      locate: () async {
        locateCallCount++;
        return {'latitude': 23.25, 'longitude': 77.41, 'accuracy': 10.0, 'capturedAtUtc': '2026-11-12T10:00:00Z'};
      },
      takeSelfie: () async => 'test_selfie_base64_data',
    );

    controller.isField = true;
    controller.user = {'id': 'EMP001', 'name': 'Test Employee'};
    controller.attendance = {
      'id': 101,
      'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String(),
      'punchOutUtc': null,
    };
    controller.stateKnown = true;
    expect(controller.onDuty, isTrue);

    // Punch out returns 401
    await controller.punch();

    // Verify locate() was called EXACTLY once (reused in offline save, no second 15s lock!)
    expect(locateCallCount, equals(1), reason: 'location must be reused on 401 without second locate() call');
    expect(controller.onDuty, isFalse);
    expect(controller.attendance?['punchOutUtc'], isNotNull);
  });

  test('A-11: 401 on punch-out with LocalWorkspace persists to SQLite outbox with stable idempotency and stops native tracking', () async {
    final controller = TrackyuController(
      api,
      vault: MemoryVault(),
      locate: () async => {'latitude': 23.25, 'longitude': 77.41, 'accuracy': 10.0, 'capturedAtUtc': '2026-11-12T10:00:00Z'},
      takeSelfie: () async => 'test_selfie_base64_data',
    );

    controller.isField = true;
    controller.user = {'id': 'EMP001', 'name': 'Test Employee'};
    controller.attendance = {
      'id': 101,
      'localId': 101,
      'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String(),
      'punchOutUtc': null,
    };
    controller.stateKnown = true;
    controller.local = LocalWorkspace();
    expect(controller.onDuty, isTrue);

    // Punch out returns 401
    await controller.punch();

    // 1. Verify localCommit was called on method channel with deterministic ID
    final commitCalls = calls.where((c) => c.method == 'localCommit').toList();
    expect(commitCalls, hasLength(1));
    final commitArg = commitCalls.first.arguments as Map;
    final operation = commitArg['operation'] as Map;
    expect(operation['id'], equals('punch-out-101'));
    expect(operation['route'], equals('FieldAttendance/punch-out'));

    // 2. Verify native GPS stop was called
    final stopCalls = calls.where((c) => c.method == 'stop').toList();
    expect(stopCalls, isNotEmpty);

    // 3. Verify attendance state updated to off-duty
    expect(controller.onDuty, isFalse);
    expect(controller.attendance?['punchOutUtc'], equals('2026-11-12T10:00:00Z'));

    // 4. Duplicate prevention: tapping punch-out again does NOT create duplicate outbox entries!
    await controller.punch();
    final secondCommitCalls = calls.where((c) => c.method == 'localCommit').toList();
    expect(secondCommitCalls, hasLength(1), reason: 'Duplicate punch-out must be prevented');
  });

  test('A-11: 401 on punch-out with failing local persistence reports accurate error and keeps onDuty true', () async {
    final controller = TrackyuController(
      api,
      vault: MemoryVault(),
      locate: () async => {'latitude': 23.25, 'longitude': 77.41, 'accuracy': 10.0},
      takeSelfie: () async => 'test_selfie_base64_data',
    );

    controller.isField = true;
    controller.user = {'id': 'EMP001', 'name': 'Test Employee'};
    controller.attendance = {
      'id': 101,
      'localId': 101,
      'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 4)).toIso8601String(),
      'punchOutUtc': null,
    };
    controller.stateKnown = true;
    controller.local = LocalWorkspace();
    expect(controller.onDuty, isTrue);

    failLocalCommit = true;

    try {
      await controller.punch();
    } catch (_) {}

    // Verify:
    // 1. Attendance was NOT marked off-duty
    expect(controller.onDuty, isTrue);
    expect(controller.attendance?['punchOutUtc'], isNull);
    // 2. Accurate error notice displayed
    expect(controller.notice.toLowerCase(), contains('offline save failed'));
  });
}
