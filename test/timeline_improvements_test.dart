import 'local_workspace_test.dart' show MemoryWorkspace;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'package:fieldforce_hrms/trackyu/tracking_status.dart';
import 'trackyu_integration_test.dart' show Adapter, reply, MemoryVault;

import 'package:fieldforce_hrms/trackyu/timeline_reconciliation.dart';

Json withEvidence(Map source) {
  final report = Map<String, dynamic>.from(source);
  final day = businessDay(DateTime.now());
  void rewrite(dynamic value) {
    if (value is Map) {
      for (final key in value.keys.toList()) {
        final item = value[key];
        if (item is String && item.startsWith('2026-11-08'))
          value[key] = item
              .replaceFirst('2026-11-08', day)
              .replaceFirst('18:46', '16:46');
        else
          rewrite(item);
      }
    } else if (value is List) {
      for (final item in value) rewrite(item);
    }
  }

  rewrite(report);
  final route = report['route'];
  if (route is Map) {
    final points = <Json>[];
    route['segments']=[]; // The raw fixture below is the complete recording evidence.
    for (final raw in route['stops'] as List? ?? []) {
      final stop = raw as Map;
      final start = DateTime.parse(stop['startUtc']),
          end = DateTime.parse(stop['endUtc']);
      for (
        var at = start;
        !at.isAfter(end);
        at = at.add(const Duration(minutes: 1))
      )
        points.add({
          'latitude': stop['latitude'],
          'longitude': stop['longitude'],
          'capturedAtUtc': at.toIso8601String(),
          'accuracyMeters': 10,
          'attendanceId': 1,
          'mode': 'Field',
        });
    }
    points.sort(
      (a, b) => '${a['capturedAtUtc']}'.compareTo('${b['capturedAtUtc']}'),
    );
    report['recordedPoints'] = points;
  }
  return report;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  testWidgets(
    'TrackingStatusCard displays happy emoji when location permission is active',
    (tester) async {
      DutyTracker.platformOverride = true;
      addTearDown(() => DutyTracker.platformOverride = null);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('trackyu/duty_tracking'),
            (call) async {
              if (call.method == 'status') {
                return {
                  'userId': '',
                  'baseUrl': 'https://test.example/api',
                  'active': true,
                  'precisePermission': true,
                  'backgroundPermission': true,
                  'batteryUnrestricted': true,
                };
              }
              return null;
            },
          );

      final dio = Dio()..httpClientAdapter = Adapter((r) => reply({}));
      final controller = TrackyuController(
        TrackyuApi('https://test.example/api', client: dio),
        vault: MemoryVault(),
      );

      controller.local = MemoryWorkspace(
        withEvidence(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TrackingStatusCard(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      // Verify happy emoji and positive permission text
      expect(find.textContaining('😊'), findsOneWidget);
      expect(find.text('Location permission active'), findsOneWidget);
      expect(find.textContaining('Allow background battery use'), findsNothing);

      controller.local = MemoryWorkspace(
        withEvidence(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'DutyRoutePage shows stop address, mini-map on select, and visit details modal sheet',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (r) => reply({
            'route': {
              'segments': [
                [
                  {
                    'latitude': 28.5355,
                    'longitude': 77.3910,
                    'capturedAtUtc': '2026-11-08T09:00:00Z',
                    'accuracyMeters': 10,
                  },
                  {
                    'latitude': 28.5356,
                    'longitude': 77.3911,
                    'capturedAtUtc': '2026-11-08T09:30:00Z',
                    'accuracyMeters': 10,
                  },
                ],
              ],
              'stops': [
                {
                  'latitude': 28.5355,
                  'longitude': 77.3910,
                  'startUtc': '2026-11-08T09:03:00Z',
                  'endUtc': '2026-11-08T09:35:00Z',
                  'address': 'Logix Cyber Park, Sector 62, Noida',
                },
              ],
            },
            'visits': [
              {
                'id': 'v-101',
                'shopName': 'Test Retailer Store',
                'inLatitude': 28.5360,
                'inLongitude': 77.3920,
                'checkInUtc': '2026-11-08T10:00:00Z',
                'checkOutUtc': '2026-11-08T10:25:00Z',
                'address': 'Plot 4, Block B, Industrial Area',
                'remarks': 'Discussed stock requirements and order volume',
              },
            ],
            'events': [
              {
                'type': 'PunchIn',
                'title': 'Punch-in',
                'atUtc': '2026-11-08T09:00:00Z',
              },
            ],
          }),
        );
      final controller = TrackyuController(
        TrackyuApi('https://test.example/api', client: dio),
        vault: MemoryVault(),
      );

      controller.local = MemoryWorkspace(
        withEvidence(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: DutyRoutePage(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Scroll to bring Stop item well into view
      await tester.scrollUntilVisible(
        find.text('Logix Cyber Park, Sector 62, Noida'),
        300,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      // 1. Task 1: Stop Address is displayed as prominent title
      expect(find.text('Logix Cyber Park, Sector 62, Noida'), findsOneWidget);
      expect(find.textContaining('Stop 1 •'), findsOneWidget);
      expect(find.text('32 min'), findsAtLeastNWidgets(1));

      // Tap on Stop 1 to reveal mini-map and focus
      await tester.tap(find.text('Logix Cyber Park, Sector 62, Noida'));
      await tester.pumpAndSettle();
      expect(find.text('Focused on map'), findsOneWidget);

      // 2. Task 3: Visit Tile is styled with OPEN VISIT tag, store name and remarks preview
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(find.text('OPEN VISIT'), findsOneWidget);
      expect(find.text('Test Retailer Store'), findsAtLeastNWidgets(1));
      expect(
        find.textContaining('Discussed stock requirements'),
        findsOneWidget,
      );
      expect(find.text('Tap for full visit details'), findsOneWidget);

      // Tap on Visit Tile to open modal bottom sheet
      await tester.tap(find.text('Tap for full visit details'));
      await tester.pumpAndSettle();

      // Verify modal bottom sheet details
      expect(find.text('OPEN VISIT DETAILS'), findsOneWidget);
      expect(find.text('CHECK IN'), findsOneWidget);
      expect(find.text('CHECK OUT'), findsOneWidget);
      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(find.text('Plot 4, Block B, Industrial Area'), findsNWidgets(2));
      expect(find.text('Remarks / Notes'), findsOneWidget);
      expect(find.text('Show this visit on map'), findsOneWidget);

      // Close bottom sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('OPEN VISIT DETAILS'), findsNothing);

      controller.local = MemoryWorkspace(
        withEvidence(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'consecutive stops at same location are merged into a single stop until location changes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (r) => reply({
            'route': {
              'segments': [],
              'stops': [
                {
                  'latitude': 23.1800,
                  'longitude': 77.4200,
                  'startUtc': '2026-11-08T10:12:00Z',
                  'endUtc': '2026-11-08T10:24:00Z',
                  'address': 'D-36, Naya Pura, Kolar',
                },
                {
                  'latitude': 23.1801,
                  'longitude': 77.4201,
                  'startUtc': '2026-11-08T11:10:00Z',
                  'endUtc': '2026-11-08T11:24:00Z',
                  'address': 'D-36, Naya Pura, Kolar',
                },
                {
                  'latitude': 23.1800,
                  'longitude': 77.4200,
                  'startUtc': '2026-11-08T11:30:00Z',
                  'endUtc': '2026-11-08T11:44:00Z',
                  'address': 'D-36, Naya Pura, Kolar',
                },
                {
                  'latitude': 23.1950,
                  'longitude': 77.4350,
                  'startUtc': '2026-11-08T14:05:00Z',
                  'endUtc': '2026-11-08T14:20:00Z',
                  'address': 'Kolar Rd, Bhopal',
                },
                {
                  'latitude': 23.1800,
                  'longitude': 77.4200,
                  'startUtc': '2026-11-08T14:21:00Z',
                  'endUtc': '2026-11-08T14:48:00Z',
                  'address': 'D-36, Naya Pura, Kolar',
                },
                {
                  'latitude': 23.1802,
                  'longitude': 77.4201,
                  'startUtc': '2026-11-08T14:58:00Z',
                  'endUtc': '2026-11-08T18:46:00Z',
                  'address': 'D-36, Naya Pura, Kolar',
                },
              ],
            },
            'visits': [],
            'events': [],
          }),
        );
      final controller = TrackyuController(
        TrackyuApi('https://test.example/api', client: dio),
        vault: MemoryVault(),
      );

      controller.local = MemoryWorkspace(
        withEvidence(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: DutyRoutePage(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Verify exactly 3 stops exist instead of 6:
      // 1. First merged D-36 stop: Stop 1
      // 2. Kolar Rd stop: Stop 2
      // 3. Second merged D-36 stop: Stop 3
      expect(find.textContaining('Stop 1 •'), findsOneWidget);
      expect(find.textContaining('Stop 2 •'), findsOneWidget);
      expect(find.textContaining('Stop 3 •'), findsOneWidget);
      expect(find.textContaining('Stop 4 •'), findsNothing);

      // Stop 2 is Kolar Rd, Bhopal
      expect(find.text('Kolar Rd, Bhopal'), findsOneWidget);

      // D-36 appears exactly 2 times (morning block and evening block)
      expect(find.text('D-36, Naya Pura, Kolar'), findsNWidgets(2));

      controller.local = MemoryWorkspace(
        withEvidence(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
