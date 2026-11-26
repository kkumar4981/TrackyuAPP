import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/working_hours.dart';
import 'trackyu_integration_test.dart'
    show MemoryVault, Adapter, reply, testSelfie;

void main() {
  late TrackyuController c;
  late List<RequestOptions> requests;
  String? photo;
  dynamic record;
  late String now;
  late int captures, fixes;
  setUp(() {
    photo = testSelfie;
    record = null;
    now = '2026-11-07T09:15:00Z';
    captures = 0;
    fixes = 0;
    requests = [];
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) {
        requests.add(r);
        if (r.path == 'Auth/login') {
          return reply({
            'token': 'test-token',
            'user': {'SM_USER_ID': 'WF1', 'NAME': 'Test employee'},
          });
        }
        if (r.path == 'AttendanceProfile/mine') return reply({'mode': 'Field'});
        if (r.path == 'FieldAttendance/state') {
          return reply({
            'workDate': '2026-11-07',
            'serverTimeUtc': now,
            'attendance': record,
          });
        }
        if (r.path == 'FieldAttendance/punch-in') {
          record = {
            'id': 17,
            'punchInUtc': now,
            'punchOutUtc': null,
            'serverTimeUtc': now,
          };
          return reply(record);
        }
        if (r.path == 'FieldAttendance/punch-out') {
          record = {...record as Map, 'punchOutUtc': now, 'serverTimeUtc': now};
          return reply(record);
        }
        return reply(null, status: 404, success: false, code: 'NOT_FOUND');
      });
    final api = TrackyuApi(
      'https://test.example/api',
      client: dio,
      deviceIdentity: () async => {
        'deviceId': 'test:fixture-device-01',
        'deviceName': 'Test phone',
      },
    );
    c = TrackyuController(
      api,
      vault: MemoryVault(),
      takeSelfie: () async {
        captures++;
        return photo;
      },
      locate: () async {
        fixes++;
        return {
          'latitude': 19,
          'longitude': 72,
          'accuracyMeters': 8,
          'capturedAtUtc': now,
        };
      },
    );
  });
  tearDown(() => c.dispose());
  test(
    'camera cancellation creates no GPS request or attendance write',
    () async {
      await c.login('WF1', 'secret');
      photo = null;
      requests.clear();
      await c.punch();
      expect(captures, 1);
      expect(fixes, 0);
      expect(requests, isEmpty);
      expect(c.onDuty, isFalse);
    },
  );
  test(
    'selfie belongs to punch-in only and final working hours are server-based',
    () async {
      await c.login('WF1', 'secret');
      await c.punch();
      expect((requests.last.data as Map)['selfieBase64'], testSelfie);
      now = '2026-11-07T11:45:00Z';
      photo = null;
      await c.punch();
      expect(captures, 1);
      expect((requests.last.data as Map).containsKey('selfieBase64'), isFalse);
      expect(c.workingDuration, const Duration(hours: 2, minutes: 30));
      c.syncServerTime('2036-01-01T00:00:00Z');
      expect(c.workingDuration, const Duration(hours: 2, minutes: 30));
    },
  );
  test(
    'restored open overnight session uses server time instead of device wall clock',
    () async {
      now = '2026-11-07T02:15:00Z';
      record = {
        'id': 17,
        'punchInUtc': '2026-11-06T23:15:00Z',
        'punchOutUtc': null,
      };
      await c.login('WF1', 'secret');
      expect(c.workingDuration!.inHours, 3);
      expect(hoursLabel(c.workingDuration), startsWith('03:00:'));
    },
  );
  testWidgets(
    'home timer shows open hours and stops after confirmed punch-out',
    (tester) async {
      record = {
        'id': 17,
        'punchInUtc': '2026-11-07T06:15:00Z',
        'punchOutUtc': null,
      };
      await tester.runAsync(() => c.login('WF1', 'secret'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WorkingHoursDisplay(controller: c)),
        ),
      );
      await tester.pump();
      expect(find.textContaining(RegExp(r'^03:00:\d{2}$')), findsOneWidget);
      expect(find.text('Live since punch-in'), findsOneWidget);
      final initial = hoursLabel(c.workingDuration);
      final requestCount = requests.length;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(hoursLabel(c.workingDuration), isNot(initial));
      expect(requests.length, requestCount);
      record = {...record as Map, 'punchOutUtc': '2026-11-07T08:45:00Z'};
      await tester.runAsync(() => c.refresh());
      await tester.pump();
      expect(find.text('02:30:00'), findsOneWidget);
      expect(find.text('Final duration'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
