import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'trackyu_integration_test.dart'
    show Adapter, reply, MemoryVault, testSelfie;

void main() {
  late TrackyuController session;
  late VisitsData data;
  late List<RequestOptions> calls;
  late List<Json> records;
  String? photo;
  bool timeout = false;
  int gps = 0;
  setUp(() {
    calls = [];
    records = [];
    photo = testSelfie;
    timeout = false;
    gps = 0;
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) {
        calls.add(r);
        if (r.path == 'AttendanceProfile/mine') return reply({'mode': 'Field'});
        if (r.path == 'MobileMenus') {
          return reply([
            {'key': 'visits', 'enabled': true},
          ]);
        }
        if (r.path == 'FieldAttendance/state') {
          return reply({
            'attendance': session.attendance,
            'workDate': '2026-11-07',
            'serverTimeUtc': '2026-11-07T09:00:00Z',
          });
        }
        if (r.path.startsWith('MobileVisits/mine')) return reply(records);
        if (r.path == 'MobileVisits/start') {
          records = [
            {
              'id': 7,
              'requestId': (r.data as Map)['requestId'],
              'kind': 'Open',
              'shopName': 'Test shop',
              'checkOutUtc': null,
              'version': 'AAAAAAAAAAA=',
            },
          ];
          if (timeout) {
            throw DioException(
              requestOptions: r,
              type: DioExceptionType.receiveTimeout,
            );
          }
          return reply({'id': 7});
        }
        if (r.path == 'MobileVisits/finish') {
          records = [
            {
              ...records.first,
              'checkOutUtc': '2026-11-07T10:00:00Z',
              'closeRequestId': (r.data as Map)['requestId'],
            },
          ];
          return reply({'id': 7});
        }
        return reply([]);
      });
    session = TrackyuController(
      TrackyuApi('https://workspace.test/api', client: dio),
      vault: MemoryVault(),
      locate: () async {
        gps++;
        return {
          'latitude': 19,
          'longitude': 72,
          'accuracyMeters': 5,
          'capturedAtUtc': '2026-11-07T09:00:00Z',
        };
      },
    );
    session.user = {'SM_USER_ID': 'QA1', 'NAME': 'QA'};
    session.enabledMenus = {'visits'};
    session.stateKnown = true;
    session.isField = true;
    session.attendance = {
      'id': 1,
      'punchInUtc': '2026-11-07T08:00:00Z',
      'punchOutUtc': null,
    };
    session.syncServerTime('2026-11-07T09:00:00Z');
    data = VisitsData(session, capture: () async => photo);
  });

  test('off-duty visit never opens camera or captures GPS', () async {
    session.attendance = null;
    var camera = 0;
    final blocked = VisitsData(
      session,
      capture: () async {
        camera++;
        return testSelfie;
      },
    );
    await expectLater(
      blocked.save(finish: false, fields: {'kind': 'Open'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(camera, 0);
    expect(gps, 0);
    expect(calls.any((r) => r.path == 'MobileVisits/start'), isFalse);
    blocked.dispose();
  });
  test('cutoff and punch-out prevent visits', () {
    session.syncServerTime('2026-11-07T17:30:00Z');
    expect(session.canVisit, isFalse);
    session.attendance!['punchOutUtc'] = '2026-11-07T10:00:00Z';
    expect(session.canVisit, isFalse);
  });
  tearDown(() {
    data.dispose();
    session.dispose();
  });
  test('retailer visit checkout becomes available at the server deadline', () {
    final row = <String, dynamic>{
      'earliestCheckoutUtc': '2026-11-07T10:10:00Z',
    };
    expect(
      visitCheckoutReady(row, DateTime.parse('2026-11-07T10:09:59Z')),
      isFalse,
    );
    expect(
      visitCheckoutReady(row, DateTime.parse('2026-11-07T10:10:00Z')),
      isTrue,
    );
  });
  testWidgets('home salesman visit shortcut opens punch screen directly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesmanVisitShortcut(controller: session)),
      ),
    );
    await tester.tap(find.text('Open visit'));
    await tester.pumpAndSettle();
    expect(find.text('Open visits'), findsWidgets);
    expect(find.text('Start Open Visit'), findsOneWidget);
    expect(calls.any((r) => r.path.startsWith('MobileVisits/mine')), isTrue);
    expect(calls.any((r) => r.path == 'Portal/visits'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rapid multiple clicks on Start Open Visit do not open duplicate instances', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VisitsPage(controller: session)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start Open Visit'), findsOneWidget);

    // Rapid taps on Start Open Visit
    await tester.tap(find.text('Start Open Visit'));
    await tester.tap(find.text('Start Open Visit'));
    await tester.tap(find.text('Start Open Visit'));
    await tester.pumpAndSettle();

    // Only one VisitForm route should be on screen
    expect(find.byType(VisitForm), findsOneWidget);
    expect(find.text('Photo & punch in'), findsOneWidget);

    // Dismiss the form
    Navigator.of(tester.element(find.byType(VisitForm))).pop(true);
    await tester.pumpAndSettle();

    // After pop, we must be back on VisitsPage, NOT another VisitForm instance!
    expect(find.byType(VisitForm), findsNothing);
    expect(find.byType(VisitsPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cannot start open visit when a visit is already in progress', (
    tester,
  ) async {
    // Set an active visit
    records = [
      {
        'id': 99,
        'kind': 'Open',
        'shopName': 'Existing Shop',
        'checkOutUtc': null,
        'version': 'AAAAAAAAAAA=',
      }
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VisitsPage(controller: session)),
      ),
    );
    await tester.pumpAndSettle();

    // "Start Open Visit" should not even be rendered because active != null
    expect(find.text('Start Open Visit'), findsNothing);

    // Active visit card should show Punch Out button
    expect(find.text('Punch Out'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('cancelling the visit camera prevents GPS and submission', () async {
    photo = null;
    expect(await data.save(finish: false, fields: {'kind': 'Open'}), isFalse);
    expect(calls.any((r) => r.path.startsWith('MobileVisits/')), isFalse);
    expect(gps, 0);
    expect(data.saving, isFalse);
  });
  test(
    'open visit requires arrival and departure selfies with fresh GPS',
    () async {
      await data.save(
        finish: false,
        fields: {'kind': 'Open', 'shopName': 'Test shop'},
      );
      expect(
        (calls.firstWhere((r) => r.path == 'MobileVisits/start').data
            as Map)['photoBase64'],
        testSelfie,
      );
      expect(data.active?['id'], 7);
      photo = testSelfie;
      await data.save(
        finish: true,
        fields: {
          'id': 7,
          'version': 'AAAAAAAAAAA=',
          'remark': 'Customer visited',
        },
      );
      final out = calls.firstWhere((r) => r.path == 'MobileVisits/finish');
      expect((out.data as Map).containsKey('photoBase64'), isFalse);
      expect(out.data['departureSelfieBase64'], testSelfie);
      expect(out.data['version'], 'AAAAAAAAAAA=');
      expect(gps, 2);
      expect(data.active, isNull);
    },
  );
  test(
    'lost response does not replay and reload reconciles request key before another visit',
    () async {
      final oldKey = data.startKey;
      timeout = true;
      await expectLater(
        data.save(finish: false, fields: {'kind': 'Open'}),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls.where((r) => r.path == 'MobileVisits/start'), hasLength(1));
      expect(data.startKey, oldKey);
      await data.load();
      expect(data.active?['id'], 7);
      expect(data.startKey, isNot(oldKey));
    },
  );
  testWidgets(
    'open visit form validates contact fields and fits a narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: VisitForm(
            data: data,
            visit: {
              'id': 7,
              'kind': 'Open',
              'shopName': 'Customer shop',
              'version': 'AAAAAAAAAAA=',
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Selfie & punch out'));
      await tester.tap(find.text('Selfie & punch out'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a ten-digit mobile number.'), findsOneWidget);
      expect(calls.any((r) => r.path.startsWith('MobileVisits/')), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'offline mode loads cached visits without error and saves open visit locally with sync queue',
    () async {
      session.setOffline(true);
      await data.load();
      expect(data.error, isNull);
      final saved = await data.save(
        finish: false,
        fields: {
          'kind': 'Open',
          'shopName': 'Offline Store',
          'address': 'Local Road',
        },
      );
      expect(saved, isTrue);
      expect(data.rows, hasLength(1));
      expect(data.rows.first['shopName'], 'Offline Store');
      expect(data.rows.first['isOffline'], isTrue);
      expect(session.pendingVisits, hasLength(1));
      expect(session.pendingVisits.first['finish'], isFalse);

      // Now test offline visit completion
      photo = testSelfie;
      final finished = await data.save(
        finish: true,
        fields: {
          'id': data.rows.first['id'],
          'kind': 'Open',
          'remark': 'Completed offline',
          'ownerName': 'Owner',
          'mobile': '9876543210',
          'lead': 'Y',
        },
      );
      expect(finished, isTrue);
      expect(data.rows.first['checkOutUtc'], isNotNull);
      expect(data.active, isNull);
      expect(session.pendingVisits, hasLength(2));
    },
  );
}
