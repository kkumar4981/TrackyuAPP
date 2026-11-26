import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/app.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/readiness.dart';
import 'package:fieldforce_hrms/trackyu/workspace.dart';
import 'package:fieldforce_hrms/trackyu/exports.dart';
import 'package:fieldforce_hrms/trackyu/locations.dart';

class Vault implements SessionVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String? value) async {}
  @override
  Future<String?> readPendingPunches() async => null;
  @override
  Future<void> writePendingPunches(String? value) async {}
  @override
  Future<String?> readPendingVisits() async => null;
  @override
  Future<void> writePendingVisits(String? value) async {}
  @override
  Future<String?> readCachedVisits() async => null;
  @override
  Future<void> writeCachedVisits(String? value) async {}
  @override
  Future<String?> readTheme() async => null;
  @override
  Future<void> writeTheme(String? value) async {}
}

class TestPlatform implements ReadinessPlatform {
  final events = StreamController<bool>.broadcast();
  List<SetupCheck> values = [
    const SetupCheck(SetupItem.gps, 'GPS', 'Enable GPS', true),
  ];
  bool fail = false;
  int fixes = 0;
  @override
  Stream<bool> get changes => events.stream;
  @override
  Future<List<SetupCheck>> inspect() async {
    if (fail) throw StateError('private device error');
    return values;
  }

  @override
  Future<void> fix(SetupItem item) async {
    fixes++;
  }
}

class ApiAdapter implements HttpClientAdapter {
  final List<RequestOptions> calls = [];
  bool expired = false, broken = false, member = true;
  Json? saved;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? data,
    Future<void>? cancel,
  ) async {
    calls.add(o);
    if (expired || broken) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': false,
          'message': expired
              ? 'Please sign in again.'
              : 'Temporarily unavailable',
          'errorCode': expired ? 'UNAUTHORIZED' : 'UNAVAILABLE',
        }),
        expired ? 401 : 503,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }
    dynamic result;
    if (o.path == 'Portal/profile') {
      result = {
        'mode': 'Field',
        'offices': member
            ? [
                {
                  'id': 7,
                  'name': 'Test office',
                  'isMember': true,
                  'canManage': false,
                  'isEnabled': true,
                  'timeZoneId': 'Asia/Kolkata',
                },
              ]
            : [],
      };
    } else if (o.path == 'OfficeLeave/reasons') {
      result = [
        {'id': 1, 'name': 'Personal'},
      ];
    } else if (o.path.endsWith('/save') ||
        o.path.endsWith('/apply') ||
        o.path.endsWith('/submit')) {
      saved = Map<String, dynamic>.from(o.data as Map);
      result = {'id': 99, 'version': 'next'};
    } else if (o.path == 'Portal/attendance') {
      result = {
        'rows': [
          {
            'id': 1,
            'userId': 'WF1',
            'attendanceMode': 'Field',
            'workDate': '2026-11-06',
            'punchInUtc': '2026-11-06T05:00:00Z',
          },
        ],
        'total': 1,
      };
    } else if (o.path == 'Portal/visits') {
      result = {'regular': [], 'open': []};
    } else {
      result = <Json>[];
    }
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': result}),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiAdapter adapter;
  late TrackyuController session;
  setUp(() {
    adapter = ApiAdapter();
    final api = TrackyuApi(
      'https://example.test/api',
      client: Dio()..httpClientAdapter = adapter,
      deviceIdentity: () async => {
        'deviceId': 'test:fixture-device-01',
        'deviceName': 'Test phone',
      },
    );
    session = TrackyuController(api, vault: Vault())
      ..user = {'SM_USER_ID': 'WF1', 'NAME': 'Test employee'}
      ..enabledMenus = WorkFeature.values.map((f) => f.name).toSet();
  });
  tearDown(() => session.dispose());

  testWidgets(
    'startup checklist is required and restores a preserved form after GPS changes',
    (tester) async {
      final platform = TestPlatform();
      final monitor = DeviceReadiness(platform);
      session.user = null;
      await tester.pumpWidget(
        TrackyuApp(controller: session, readiness: monitor),
      );
      await tester.pumpAndSettle();
      expect(find.text('Device setup checklist'), findsOneWidget);
      await tester.tap(find.text('Continue to Trackyu'));
      await tester.pumpAndSettle();
      platform.events.add(false);
      await tester.pumpAndSettle();
      expect(find.text('Device setup checklist'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, 'draft-user');
      platform.values = [
        const SetupCheck(SetupItem.gps, 'GPS', 'Enable GPS', false),
      ];
      platform.events.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Device setup checklist'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to Trackyu'),
            )
            .onPressed,
        isNull,
      );
      platform.values = [
        const SetupCheck(SetupItem.gps, 'GPS', 'Enable GPS', true),
      ];
      await monitor.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to Trackyu'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'draft-user',
      );
      await tester.pumpWidget(const SizedBox());
      await platform.events.close();
    },
  );

  test(
    'network, storage and background loss block, optional notifications do not',
    () async {
      final platform = TestPlatform();
      final monitor = DeviceReadiness(platform);
      for (final item in [
        SetupItem.network,
        SetupItem.storage,
        SetupItem.background,
      ]) {
        platform.values = [SetupCheck(item, 'Required', 'Fix it', false)];
        await monitor.refresh();
        expect(monitor.ready, isFalse);
        monitor.continueToApp();
        expect(monitor.blocking, isTrue);
      }
      platform.values = [
        const SetupCheck(
          SetupItem.notifications,
          'Notifications',
          'Optional',
          false,
          required: false,
        ),
      ];
      await monitor.refresh();
      monitor.continueToApp();
      expect(monitor.blocking, isFalse);
      platform.fail = true;
      await monitor.refresh();
      expect(monitor.blocking, isTrue);
      expect(monitor.error, isNot(contains('private device error')));
      monitor.dispose();
      await platform.events.close();
    },
  );

  test(
    'employee reports use server-scoped endpoints and no client employee ID',
    () async {
      for (final feature in WorkFeature.values) {
        final data = WorkspaceData(session, feature);
        await data.load();
        expect(data.error, isNull, reason: feature.title);
        for (final call in adapter.calls) {
          expect((call.data as Map?)?.containsKey('userId') ?? false, isFalse);
        }
        data.dispose();
      }
    },
  );

  test(
    'field employee without HR office keeps history and receives no office writes',
    () async {
      adapter.member = false;
      final data = WorkspaceData(session, WorkFeature.activity);
      await data.load();
      expect(data.canCreate, isFalse);
      expect(data.error, isNull);
      expect(adapter.calls.map((r) => r.path), ['Portal/profile']);
      data.dispose();
      final history = WorkspaceData(session, WorkFeature.history);
      await history.load();
      expect(history.rows.single['attendanceMode'], 'Field');
      history.dispose();
    },
  );

  test(
    'failed reads are not empty success and expired session signs out',
    () async {
      final data = WorkspaceData(session, WorkFeature.history);
      await data.load();
      adapter.broken = true;
      await data.load();
      expect(data.error, contains('Temporarily unavailable'));
      expect(data.rows, isEmpty);
      adapter.broken = false;
      adapter.expired = true;
      await data.load();
      expect(session.loggedIn, isFalse);
      data.dispose();
    },
  );

  testWidgets(
    'activity edit sends version and user values; large-font forms fit',
    (tester) async {
      final data = WorkspaceData(session, WorkFeature.activity);
      await tester.runAsync(() => data.load());
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: WorkspaceForm(
              data: data,
              row: {
                'id': 11,
                'officeId': 7,
                'version': 'original',
                'title': 'Original',
                'activityDate': dateOnly(DateTime.now()),
                'minutesSpent': 10,
                'status': 'Planned',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Updated activity',
      );
      await tester.scrollUntilVisible(
        find.text('Save'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(adapter.saved?['activityId'], 11);
      expect(adapter.saved?['version'], 'original');
      expect(adapter.saved?['title'], 'Updated activity');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets('reminder cannot save with no selected days', (tester) async {
    final data = WorkspaceData(session, WorkFeature.reminder);
    await tester.runAsync(() => data.load());
    await tester.pumpWidget(MaterialApp(home: WorkspaceForm(data: data)));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reminder title'),
      'Office reminder',
    );
    for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']) {
      await tester.tap(find.widgetWithText(FilterChip, day));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one reminder day.'), findsOneWidget);
    expect(adapter.saved, isNull);
    await tester.pumpWidget(const SizedBox());
    data.dispose();
  });

  for (final feature in [
    WorkFeature.leave,
    WorkFeature.reminder,
    WorkFeature.intimation,
  ]) {
    testWidgets('${feature.title} form submits the real API contract', (
      tester,
    ) async {
      final data = WorkspaceData(session, feature);
      await tester.runAsync(() => data.load());
      final row = feature == WorkFeature.reminder
          ? <String, dynamic>{
              'id': 17,
              'officeId': 7,
              'version': 'existing-version',
              'title': 'Existing reminder',
              'localTime': '09:15:00',
              'daysOfWeekCsv': '1,3,5',
              'isEnabled': true,
            }
          : null;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceForm(data: data, row: row),
        ),
      );
      await tester.pumpAndSettle();
      if (feature == WorkFeature.leave) {
        await tester.tap(find.byType(DropdownButtonFormField<int>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Personal').last);
        await tester.pumpAndSettle();
      }
      if (feature != WorkFeature.reminder) {
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            feature == WorkFeature.leave ? 'Remarks / details' : 'Reason',
          ),
          'QA valid request reason',
        );
      } else {
        await tester.tap(find.byType(Switch));
      }
      final saveLabel = feature == WorkFeature.intimation
          ? 'Send pre-intimation'
          : feature == WorkFeature.leave
          ? 'Apply leave'
          : 'Save';
      await tester.scrollUntilVisible(
        find.text(saveLabel),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text(saveLabel));
      await tester.tap(find.text(saveLabel));
      await tester.pumpAndSettle();
      expect(adapter.saved?['officeId'], 7);
      expect(adapter.saved?.containsKey('userId'), isFalse);
      if (feature == WorkFeature.leave) {
        expect(adapter.calls.last.path, 'OfficeLeave/apply');
        expect(adapter.saved?['portion'], 'FullDay');
        expect(adapter.saved?['fromDate'], dateOnly(DateTime.now()));
      } else if (feature == WorkFeature.reminder) {
        expect(adapter.saved?['reminderId'], 17);
        expect(adapter.saved?['version'], 'existing-version');
        expect(adapter.saved?['localTime'], '09:15');
        expect(adapter.saved?['daysOfWeekCsv'], '1,3,5');
        expect(adapter.saved?['isEnabled'], isFalse);
      } else {
        expect(adapter.calls.last.path, 'OfficePreIntimation/submit');
        expect(adapter.saved?['expectedArrivalUtc'], endsWith('Z'));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    });
  }

  test(
    'attendance export quotes cells and neutralises spreadsheet formulas',
    () {
      final csv = attendanceCsv([
        {
          'userId': '=external()',
          'workDate': '2026-11-06',
          'attendanceMode': 'Field',
          'punchInUtc': 'a,"b"\nc',
        },
      ]);
      expect(csv, contains('"\'=external()"'));
      expect(csv, contains('"a,""b""\nc"'));
      expect(csv.split('\r\n'), hasLength(2));
    },
  );
  test(
    'location map rejects missing, infinite and out-of-range coordinates',
    () {
      for (final row in <Json>[
        {},
        {'latitude': 91, 'longitude': 72},
        {'latitude': 19, 'longitude': 181},
        {'latitude': 'NaN', 'longitude': 72},
      ]) {
        expect(punchPoint(row), isNull);
      }
      expect(punchPoint({'latitude': 0, 'longitude': 0})?.latitude, 0);
    },
  );
}
