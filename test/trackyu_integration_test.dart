import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/app.dart';

class MemoryVault implements SessionVault {
  String? value;
  String? pendingPunches;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? input) async {
    value = input;
  }

  @override
  Future<String?> readPendingPunches() async => pendingPunches;
  @override
  Future<void> writePendingPunches(String? input) async {
    pendingPunches = input;
  }

  String? pendingVisits;
  String? cachedVisits;
  @override
  Future<String?> readPendingVisits() async => pendingVisits;
  @override
  Future<void> writePendingVisits(String? input) async {
    pendingVisits = input;
  }

  @override
  Future<String?> readCachedVisits() async => cachedVisits;
  @override
  Future<void> writeCachedVisits(String? input) async {
    cachedVisits = input;
  }

  String? theme;
  @override
  Future<String?> readTheme() async => theme;
  @override
  Future<void> writeTheme(String? value) async {
    theme = value;
  }
}

class Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handle;
  Adapter(this.handle);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody reply(
  dynamic data, {
  int status = 200,
  bool success = true,
  String? code,
}) => ResponseBody.fromString(
  jsonEncode({
    'success': success,
    'data': data,
    'message': success ? 'Success' : 'Safe API error',
    if (code != null) 'errorCode': code,
    if (!success) 'traceId': 'test-trace',
  }),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);
final office = <String, dynamic>{
  'id': 7,
  'name': 'Test office',
  'isEnabled': true,
};
const testSelfie =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
final location = <String, dynamic>{
  'latitude': 19.0,
  'longitude': 72.0,
  'accuracyMeters': 8.0,
  'capturedAtUtc': '2026-11-06T05:00:00Z',
};
void main() {
  late TrackyuApi api;
  late TrackyuController c;
  late MemoryVault vault;
  List<RequestOptions> calls = [];
  ResponseBody Function(RequestOptions)? extra;
  dynamic record;
  List<dynamic> assigned = [];
  String mode = 'Office';
  setUp(() {
    calls = [];
    extra = null;
    record = null;
    assigned = [office];
    mode = 'Office';
    vault = MemoryVault();
    final client = Dio();
    client.httpClientAdapter = Adapter((r) {
      calls.add(r);
      if (r.path == 'MobileMenus') {
        return reply([
          {'key': 'visits', 'enabled': true},
        ]);
      }
      if (r.path == 'AttendanceProfile/mine') return reply({'mode': mode});
      if (r.path == 'Auth/login') {
        return reply({
          'token': 'test-token',
          'user': {'name': 'Test employee', 'sM_USER_ID': 'WF1'},
        });
      }
      if (r.path == 'WorkforceOffices/mine') return reply(assigned);
      if (r.path == 'OfficeAttendance/state' ||
          r.path == 'FieldAttendance/state') {
        return reply({
          'workDate': '2026-11-06',
          'serverTimeUtc': '2026-11-06T05:00:00Z',
          'attendance': record,
        });
      }
      if (extra != null) return extra!(r);
      return reply(null, status: 404, success: false, code: 'NOT_FOUND');
    });
    api = TrackyuApi(
      'https://test.example/api/',
      client: client,
      deviceIdentity: () async => {
        'deviceId': 'test:fixture-device-01',
        'deviceName': 'Test phone',
      },
    );
    c = TrackyuController(
      api,
      vault: vault,
      locate: () async => location,
      takeSelfie: () async => testSelfie,
    );
  });
  test(
    'Login uses actual .NET contract and bearer, and stores no password',
    () async {
      await c.login(' WF1 ', ' secret ');
      expect(calls.first.uri.path, '/api/Auth/login');
      expect(calls.first.data, {
        'username': 'WF1',
        'userPassword': ' secret ',
        'clientType': 'mobile',
        'deviceId': 'test:fixture-device-01',
        'deviceName': 'Test phone',
      });
      expect(calls[1].headers['Authorization'], 'Bearer test-token');
      expect(calls[1].headers['X-Device-ID'], 'test:fixture-device-01');
      expect(vault.value, isNot(contains('secret')));
      expect(c.stateKnown, isTrue);
    },
  );
  test(
    'No assigned office blocks punching without taking GPS or sending writes',
    () async {
      assigned = [];
      await c.login('WF1', 'secret');
      expect(c.notice, contains('No office'));
      await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
      expect(calls.where((r) => r.path.contains('punch-')), isEmpty);
    },
  );
  test(
    'Late reason rejection leaves attendance unconfirmed, then exact payload succeeds',
    () async {
      await c.login('WF1', 'secret');
      extra = (r) => (r.data as Map)['lateReason'] == null
          ? reply(
              null,
              status: 400,
              success: false,
              code: 'LATE_REASON_REQUIRED',
            )
          : reply({
              'id': 99,
              'officeId': 7,
              'punchInUtc': '2026-11-06T05:00:00Z',
              'punchOutUtc': null,
            });
      await expectLater(
        c.punch(),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'code',
            'LATE_REASON_REQUIRED',
          ),
        ),
      );
      expect(c.onDuty, isFalse);
      await c.punch(reason: ' Traffic ');
      expect(c.onDuty, isTrue);
      expect(calls.last.uri.path, '/api/OfficeAttendance/punch-in');
      expect(calls.last.data, {
        'officeId': 7,
        ...location,
        'selfieBase64': testSelfie,
        'lateReason': 'Traffic',
      });
    },
  );
  test(
    'Checkout sends owned session id and early reason; completion is server confirmed',
    () async {
      record = {
        'id': 99,
        'officeId': 7,
        'punchInUtc': '2026-11-06T05:00:00Z',
        'punchOutUtc': null,
      };
      await c.login('WF1', 'secret');
      extra = (r) =>
          reply({...record as Map, 'punchOutUtc': '2026-11-06T07:00:00Z'});
      await c.punch(reason: 'Doctor appointment');
      expect(calls.last.path, 'OfficeAttendance/punch-out');
      expect((calls.last.data as Map)['attendanceId'], 99);
      expect((calls.last.data as Map)['earlyReason'], 'Doctor appointment');
      expect(c.completed, isTrue);
    },
  );
  test(
    'Timed-out punch reconciles committed state without replaying the write',
    () async {
      await c.login('WF1', 'secret');
      extra = (r) {
        record = {
          'id': 99,
          'officeId': 7,
          'punchInUtc': '2026-11-06T05:00:00Z',
          'punchOutUtc': null,
        };
        throw DioException(
          requestOptions: r,
          type: DioExceptionType.receiveTimeout,
        );
      };
      await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
      expect(c.onDuty, isTrue);
      expect(calls.where((r) => r.path.contains('punch-')).length, 1);
    },
  );
  test('Expired login on punch clears token and employee state', () async {
    await c.login('WF1', 'secret');
    extra = (r) =>
        reply(null, status: 401, success: false, code: 'UNAUTHORIZED');
    await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
    expect(c.loggedIn, isFalse);
    expect(vault.value, isNull);
    expect(api.dio.options.headers.containsKey('Authorization'), isFalse);
  });
  test(
    'Restoration never sends a saved bearer to another API server',
    () async {
      vault.value = jsonEncode({
        'server': 'https://different.example/api',
        'token': 'secret',
      });
      await c.initialize();
      expect(calls, isEmpty);
      expect(c.loggedIn, isFalse);
    },
  );
  testWidgets(
    'Legacy login validates input and slide confirms server attendance',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(TrackyuApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.textContaining('API connection'), findsNothing);
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your user name'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.enterText(find.byType(TextFormField).at(0), 'WF1');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret');
      await tester.ensureVisible(find.text('Login'));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Test employee'), findsOneWidget);
      expect(find.text('Ready to punch in'), findsOneWidget);
      extra = (r) => reply({
        'id': 99,
        'officeId': 7,
        'punchInUtc': '2026-11-06T05:00:00Z',
        'punchOutUtc': null,
      });
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Punched in'), findsOneWidget);
      expect(find.text('Slide to punch out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Field mode loads and punches with no office and no office requests',
    () async {
      mode = 'Field';
      assigned = [];
      await c.login('WF1', 'secret');
      expect(c.isField, isTrue);
      expect(c.stateKnown, isTrue);
      expect(c.notice, isEmpty);
      expect(c.officeId, isNull);
      extra = (r) => reply({
        'id': 101,
        'punchInUtc': '2026-11-06T05:00:00Z',
        'punchOutUtc': null,
      });
      await c.punch();
      expect(c.onDuty, isTrue);
      expect(calls.last.path, 'FieldAttendance/punch-in');
      expect(calls.last.data, {...location, 'selfieBase64': testSelfie});
      expect(
        calls.where(
          (r) =>
              r.path.startsWith('OfficeAttendance/') ||
              r.path == 'WorkforceOffices/mine',
        ),
        isEmpty,
      );
      extra = (r) => reply({
        'id': 101,
        'punchInUtc': '2026-11-06T05:00:00Z',
        'punchOutUtc': '2026-11-06T06:00:00Z',
      });
      await c.punch();
      expect(calls.last.path, 'FieldAttendance/punch-out');
      expect(calls.last.data, {...location, 'attendanceId': 101});
      expect(c.completed, isTrue);
    },
  );

  test(
    'Field state is restored from server without office membership',
    () async {
      mode = 'Field';
      assigned = [];
      record = {
        'id': 101,
        'punchInUtc': '2026-11-06T05:00:00Z',
        'punchOutUtc': null,
      };
      await c.login('WF1', 'secret');
      expect(c.onDuty, isTrue);
      await c.refresh();
      expect(c.onDuty, isTrue);
      expect(calls.last.path, 'FieldAttendance/state');
    },
  );

  testWidgets('Field employee sees enabled punch slider without an office', (
    tester,
  ) async {
    mode = 'Field';
    assigned = [];
    await tester.runAsync(() => c.login('WF1', 'secret'));
    await tester.pumpWidget(MaterialApp(home: AttendancePage(controller: c)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Punch from your current location.'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Punch from your current location.'),
      findsOneWidget,
    );
    expect(find.textContaining('No office is assigned'), findsNothing);
    expect(
      find.textContaining('Office assignment is not required'),
      findsNothing,
    );
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    extra = (r) => reply({
      'id': 101,
      'punchInUtc': '2026-11-06T05:00:00Z',
      'punchOutUtc': null,
    });
    await tester.drag(find.byType(Slider), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(c.onDuty, isTrue);
    await tester.scrollUntilVisible(
      find.text('Punched in'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Punched in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small login and large-text attendance do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TrackyuApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.textContaining('API connection'), findsNothing);
    expect(tester.takeException(), isNull);
    mode = 'Field';
    assigned = [];
    await tester.runAsync(() => c.login('WF1', 'secret'));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.6),
          ),
          child: AttendancePage(controller: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });

  test('HTTP failures expose safe API message and correlation id', () async {
    extra = (r) =>
        reply(null, status: 403, success: false, code: 'OUTSIDE_OFFICE');
    await expectLater(
      api.punch(false, {}),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.traceId, 'trace', 'test-trace')
            .having((e) => e.code, 'code', 'OUTSIDE_OFFICE'),
      ),
    );
  });
}
