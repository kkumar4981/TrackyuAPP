import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/workspace.dart';
import 'package:fieldforce_hrms/trackyu/attendance_summary.dart';
import 'package:fieldforce_hrms/trackyu/office_location_request.dart';
import 'trackyu_integration_test.dart' show Adapter, MemoryVault, testSelfie;
import 'workspace_readiness_test.dart' show ApiAdapter;

void main() {
  late ApiAdapter adapter;
  late TrackyuController session;
  setUp(() {
    adapter = ApiAdapter()..member = false;
    session = TrackyuController(
      TrackyuApi(
        'https://workspace.test/api',
        client: Dio()..httpClientAdapter = adapter,
      ),
      vault: MemoryVault(),
      locate: () async => {
        'latitude': 19.076,
        'longitude': 72.8777,
        'accuracyMeters': 5,
        'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
      },
    )..user = {'SM_USER_ID': 'QA1', 'NAME': 'QA employee'};
  });
  tearDown(() => session.dispose());
  testWidgets(
    'unmapped employee can apply leave with legacy reason and remarks',
    (tester) async {
      final data = WorkspaceData(session, WorkFeature.leave);
      await tester.runAsync(() => data.load());
      expect(data.canCreate, isTrue);
      await tester.pumpWidget(MaterialApp(home: WorkspaceForm(data: data)));
      await tester.pumpAndSettle();
      expect(find.text('Plan your time off'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Remarks / details'),
        'Personal appointment',
      );
      await tester.scrollUntilVisible(
        find.text('Apply leave'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Apply leave'));
      await tester.pumpAndSettle();
      expect(adapter.saved?['reasonId'], 1);
      expect(adapter.saved?['reason'], 'Personal appointment');
      expect(adapter.saved?.containsKey('officeId'), isFalse);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );
  testWidgets(
    'unmapped employee can send their own pre-intimation without an office id',
    (tester) async {
      final data = WorkspaceData(session, WorkFeature.intimation);
      await tester.runAsync(() => data.load());
      expect(data.canCreate, isTrue);
      expect(adapter.calls.last.path, 'OfficePreIntimation/personal');
      await tester.pumpWidget(MaterialApp(home: WorkspaceForm(data: data)));
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason'),
        'Traffic delay today',
      );
      await tester.scrollUntilVisible(
        find.text('Send pre-intimation'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Send pre-intimation'));
      await tester.pumpAndSettle();
      expect(adapter.saved?['reason'], 'Traffic delay today');
      expect(adapter.saved?.containsKey('officeId'), isFalse);
      expect(adapter.saved?.containsKey('userId'), isFalse);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );
  testWidgets(
    'office location proposal sends fresh GPS for review without changing office membership',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: OfficeLocationRequestPage(controller: session)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Office name'),
        'Local office',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Office address / landmark'),
        'Office road',
      );
      await tester.scrollUntilVisible(
        find.text('Send location for approval'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Send location for approval'));
      await tester.pumpAndSettle();
      expect(adapter.saved?['latitude'], 19.076);
      expect(adapter.saved?['name'], 'Local office');
      expect(
        adapter.calls.any((r) => r.path.endsWith('assign-member')),
        isFalse,
      );
      expect(session.offices, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'home summary displays a private selfie in a compact card',
    (
      tester,
    ) async {
    var requests = 0;
    final api = TrackyuApi(
      'https://workspace.test/api',
      client: Dio()
        ..httpClientAdapter = Adapter((r) {
          requests++;
          return ResponseBody.fromBytes(
            base64Decode(testSelfie),
            200,
            headers: {
              'content-type': ['image/png'],
            },
          );
        }),
      deviceIdentity: () async => {'deviceId': 'test:summary-device'},
    );
    final c = TrackyuController(api, vault: MemoryVault())
      ..user = {'SM_USER_ID': 'QA1'}
      ..isField = true
      ..stateKnown = true
      ..attendance = {
        'id': 12,
        'hasSelfie': true,
        'punchInUtc': DateTime.now().toUtc().toIso8601String(),
        'punchOutUtc': null,
      };
    c.syncServerTime(DateTime.now().toUtc().toIso8601String());
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 328,
                child: AttendanceSummary(controller: c, status: 'Punched in'),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('Check-in selfie'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(requests, 1);
    expect(
      tester.getSize(find.byType(AttendanceSummary)).height,
      lessThan(230),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 1);
    final ex = tester.takeException(); if (ex != null) { if (ex is FlutterError) { for (var d in (ex as FlutterError).diagnostics) { print('DEEP: ' + (ex as FlutterError).toStringDeep()); } } } expect(ex, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
