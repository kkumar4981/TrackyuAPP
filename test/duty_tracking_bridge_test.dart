import 'package:flutter/material.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/tracking_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'trackyu_integration_test.dart' show Adapter, reply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('full timeline pages all fixes using an IST day window', () async {
    DutyTracker.platformOverride = true;
    final requests = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, (call) async {
          final args = Map<dynamic, dynamic>.from(call.arguments as Map);
          requests.add(args);
          return List.generate(
            requests.length == 1 ? 250 : 3,
            (i) => {'id': '${args['offset']}:$i'},
          );
        });
    final rows = await DutyTracker.route(
      'FIRST',
      DateTime(2026, 11, 9),
      baseUrl: 'https://qa.example/api',
      fullResolution: true,
    );
    expect(rows.length, 253);
    expect(requests.map((r) => r['offset']), [0, 250]);
    expect(requests.first['timeline'], true);
    expect(
      requests.first['from'],
      DateTime.parse('2026-11-08T18:30:00Z').millisecondsSinceEpoch,
    );
    expect(
      requests.first['to'],
      DateTime.parse('2026-11-09T18:30:00Z').millisecondsSinceEpoch,
    );
  });
  late Json state;
  late List<MethodCall> calls;
  late TrackyuApi api;
  late int leases;
  setUp(() {
    DutyTracker.platformOverride = true;
    calls = [];
    leases = 0;
    state = {
      'userId': 'FIRST',
      'mode': 'Field',
      'attendanceId': 1,
      'active': true,
      'baseUrl': 'https://qa.example/api',
      'dutyCutoffUtc': '2099-11-07T17:30:00Z',
      'expiresAtUtc': DateTime.now()
          .toUtc()
          .add(const Duration(days: 3))
          .toIso8601String(),
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, (call) async {
          calls.add(call);
          if (call.method == 'status') return Map<String, dynamic>.from(state);
          if (call.method == 'stop') state['active'] = false;
          if (call.method == 'configure') {
            state = Map<String, dynamic>.from(call.arguments as Map);
          }
          return null;
        });
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) {
        leases++;
        return reply({
          'userId': 'SECOND',
          'trackingKey': 'scoped-write-only-test-key',
          'dutyCutoffUtc': '2099-11-07T17:30:00Z',
          'expiresAtUtc': DateTime.now()
              .add(const Duration(days: 30))
              .toUtc()
              .toIso8601String(),
          'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
        });
      });
    api = TrackyuApi(
      'https://qa.example/api',
      client: dio,
      deviceIdentity: () async => {'deviceId': 'qa-test-phone-123456789'},
    );
  });
  tearDown(() {
    DutyTracker.platformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, null);
  });
  test(
    'switching account stops previous duty before configuring new owner even with the same numeric attendance id',
    () async {
      await DutyTracker.reconcile(api, 'Field', {
        'id': 1,
        'punchOutUtc': null,
      }, userId: 'SECOND');
      expect(calls.where((c) => c.method == 'stop'), hasLength(1));
      expect(calls.where((c) => c.method == 'resume'), isEmpty);
      expect(leases, 1);
      final config =
          calls.singleWhere((c) => c.method == 'configure').arguments as Map;
      expect(config['userId'], 'SECOND');
      expect(config['active'], isTrue);
      expect(config.containsKey('token'), isFalse);
    },
  );
  test(
    'another account without a duty session cannot continue the former employee route',
    () async {
      await DutyTracker.reconcile(api, 'Field', null, userId: 'SECOND');
      expect(state['active'], isFalse);
      expect(leases, 0);
      expect(calls.where((c) => c.method == 'configure'), isEmpty);
    },
  );
  test(
    'same active session resumes without rotating its scoped key; confirmed punch-out stops collection',
    () async {
      await DutyTracker.reconcile(api, 'Field', {
        'id': 1,
        'punchOutUtc': null,
      }, userId: 'FIRST');
      expect(calls.where((c) => c.method == 'resume'), hasLength(1));
      expect(leases, 0);
      await DutyTracker.reconcile(api, 'Field', {
        'id': 1,
        'punchOutUtc': DateTime.now().toUtc().toIso8601String(),
      }, userId: 'FIRST');
      expect(state['active'], isFalse);
      expect(calls.where((c) => c.method == 'sync'), hasLength(2));
    },
  );
  test('startup cannot resume a different owner or workspace', () async {
    await DutyTracker.resume(userId: 'SECOND', baseUrl: api.baseUrl);
    await DutyTracker.resume(
      userId: 'FIRST',
      baseUrl: 'https://different.example/api',
    );
    expect(calls.where((c) => c.method == 'resume'), isEmpty);
  });
  testWidgets(
    'home never displays another employee last fix or pending count',
    (tester) async {
      state['pendingCount'] = 42;
      state['lastPoint'] = {
        'latitude': 19.076,
        'longitude': 72.8777,
        'accuracyMeters': 5,
        'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
      };
      final controller = TrackyuController(api)
        ..user = {'SM_USER_ID': 'SECOND'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TrackingStatusCard(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tracking starts at your punch-in'), findsOneWidget);
      expect(find.textContaining('GPS accuracy:'), findsNothing);
      expect(find.textContaining('42 saved locations'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
