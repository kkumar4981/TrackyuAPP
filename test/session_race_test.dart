import 'dart:async';
import 'local_workspace_test.dart' show MemoryWorkspace;
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';

class TestVault implements SessionVault {
  String? value;
  String? pendingPunches;
  String? pendingVisits;
  String? cachedVisits;
  String? theme;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? input) async => value = input;

  @override
  Future<String?> readPendingPunches() async => pendingPunches;
  @override
  Future<void> writePendingPunches(String? input) async => pendingPunches = input;

  @override
  Future<String?> readPendingVisits() async => pendingVisits;
  @override
  Future<void> writePendingVisits(String? input) async => pendingVisits = input;

  @override
  Future<String?> readCachedVisits() async => cachedVisits;
  @override
  Future<void> writeCachedVisits(String? input) async => cachedVisits = input;

  @override
  Future<String?> readTheme() async => theme;
  @override
  Future<void> writeTheme(String? v) async => theme = v;
}

class TestAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handle;
  TestAdapter(this.handle);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonReply(
  dynamic data, {
  int status = 200,
  bool success = true,
  String? code,
}) => ResponseBody.fromString(
  jsonEncode({
    'success': success,
    'data': data,
    'message': success ? 'Success' : 'Error',
    if (code != null) 'errorCode': code,
  }),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DutyTracker.platformOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, (call) async {
      if (call.method == 'status') {
        return <String, dynamic>{
          'active': false,
          'userId': 'TEST',
          'baseUrl': 'https://test.example/api',
        };
      }
      return null;
    });
  });

  for (final useLocalWorkspace in [false, true]) {
  test('Real TrackyuController: delayed refresh preserves B (local workspace: $useLocalWorkspace)', () async {
    final vault = TestVault();
    final stateCompleter = Completer<ResponseBody>();
    final requestEnteredFlight = Completer<void>();
    bool delayFieldState = false;

    final client = Dio();
    client.httpClientAdapter = TestAdapter((options) async {
      final path = options.path;

      if (path == 'MobileMenus') {
        return jsonReply([{'key': 'visits', 'enabled': true}]);
      }
      if (path == 'AttendanceProfile/mine') {
        return jsonReply({'mode': 'Field', 'isField': true});
      }
      if (path == 'Auth/login') {
        final body = options.data as Map;
        final username = body['username'] as String;
        return jsonReply({
          'token': 'jwt-token-for-$username',
          'user': {
            'name': username == 'SM488' ? 'Suresh Kumar' : 'Ankur',
            'sM_USER_ID': username,
            'id': username,
          },
        });
      }
      if (path.startsWith('MobileVisits/mine')) return jsonReply([]);
      if (path == 'WorkforceOffices/mine') {
        return jsonReply([]);
      }
      if (path == 'FieldAttendance/state') {
        if (delayFieldState) {
          if (!requestEnteredFlight.isCompleted) {
            requestEnteredFlight.complete();
          }
          return await stateCompleter.future;
        }
        return jsonReply({
          'workDate': '2026-11-17',
          'serverTimeUtc': '2026-11-17T06:00:00Z',
          'attendance': null,
        });
      }
      if (path == 'DutyTracking/lease') {
        return jsonReply({'active': true});
      }
      return jsonReply(null, status: 404, success: false);
    });

    final api = TrackyuApi(
      'https://test.example/api/',
      client: client,
      deviceIdentity: () async => {'deviceId': 'device-test-01'},
    );

    final controller = TrackyuController(
      api,
      vault: vault,
      locate: () async => {'latitude': 19.076, 'longitude': 72.877, 'accuracyMeters': 10.0},
      takeSelfie: () async => 'dummy-selfie-bytes',
    );

    // 1. User A (Suresh Kumar, SM488) logs in normally
    await controller.login('SM488', 'secret488');
    expect(controller.loggedIn, isTrue);
    expect(controller.user?['sM_USER_ID'], 'SM488');

    if (useLocalWorkspace) controller.local = MemoryWorkspace();

    // 2. Enable delay on next FieldAttendance/state, then trigger refresh() for Suresh
    delayFieldState = true;
    final refreshFuture = controller.refresh();

    // Deterministic synchronization barrier: wait until refresh() has entered flight and suspended
    await requestEnteredFlight.future;

    // 3. User A signs out while request is pending in flight
    await controller.signOut();
    expect(controller.loggedIn, isFalse);

    // 4. User B (Ankur, SM474) logs in (without delaying his initial state)
    delayFieldState = false;
    await controller.login('SM474', 'secret474');
    expect(controller.loggedIn, isTrue);
    expect(controller.user?['sM_USER_ID'], 'SM474');
    expect(controller.attendance, isNull);

    final workspaceB = MemoryWorkspace();
    final bDay = <String, dynamic>{
      'attendance': {'id': 555, 'userId': 'SM474', 'workDate': controller.localDay,
        'punchInUtc': DateTime.now().toUtc().toIso8601String(), 'punchOutUtc': null},
      'visits': [{'id': 888, 'userId': 'SM474', 'shopName': 'QA B retained record'}],
    };
    if (useLocalWorkspace) {
      controller.local = workspaceB;
      await workspaceB.write(controller.dayKey, bDay);
      controller.attendance = Map<String, dynamic>.from(bDay['attendance'] as Map);
    }
    final expectedBDay = jsonEncode(await workspaceB.read(controller.dayKey));

    // Perform User B employee-scoped workspace writes: attendance punch & cached visit
    await vault.writePendingPunches(jsonEncode([
      {
        'userId': 'SM474',
        'attendanceId': 555,
        'punchInUtc': '2026-11-17T06:05:00Z',
        'status': 'offline_pending',
      }
    ]));
    await vault.writeCachedVisits(jsonEncode([
      {
        'visitId': 888,
        'userId': 'SM474',
        'partyName': 'Apex Healthcare',
        'status': 'in_progress',
      }
    ]));
    await controller.setTheme('dark');
    expect(await vault.readTheme(), 'dark', reason: 'User B theme write must be recorded');

    // 5. Release delayed FieldAttendance/state response containing Suresh Kumar's attendance record (ID 9999)
    stateCompleter.complete(jsonReply({
      'workDate': '2026-11-17',
      'serverTimeUtc': '2026-11-17T06:00:00Z',
      'attendance': {
        'id': 9999,
        'userId': 'SM488',
        'punchInUtc': '2026-11-17T04:30:00Z',
        'punchOutUtc': null,
      },
    }));

    // Wait for the delayed refresh() Future to complete
    await refreshFuture;

    // 6. VERIFY: User B's state remains intact and was NOT corrupted by User A's delayed response
    expect(controller.user?['sM_USER_ID'], 'SM474',
        reason: 'User B must remain the active authenticated user');
    expect(controller.attendance?['id'], isNot(9999),
        reason: 'User A delayed attendance record must be rejected by F18 sessionValid guard');
    expect(await vault.readTheme(), 'dark',
        reason: 'User B workspace write must remain intact and uncorrupted after User A response discarded');

    if (useLocalWorkspace) {
      expect(identical(controller.local, workspaceB), isTrue);
      expect(jsonEncode(await workspaceB.read(controller.dayKey)), expectedBDay,
          reason: 'B employee day attendance/visit writes must survive A response');
      expect(controller.attendance?['id'], 555);
    }

    // Verify User B's employee-scoped attendance and visit records are completely uncorrupted
    final pendingPunches = jsonDecode((await vault.readPendingPunches())!) as List;
    expect(pendingPunches.length, 1);
    expect(pendingPunches.first['userId'], 'SM474',
        reason: 'User B pending punch must not be overwritten by User A punch');
    expect(pendingPunches.first['attendanceId'], 555);

    final cachedVisits = jsonDecode((await vault.readCachedVisits())!) as List;
    expect(cachedVisits.length, 1);
    expect(cachedVisits.first['userId'], 'SM474',
        reason: 'User B cached visits must not be cleared or corrupted');
    expect(cachedVisits.first['visitId'], 888);
    controller.dispose();
  });
  }
}
