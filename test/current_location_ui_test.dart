import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'package:fieldforce_hrms/trackyu/tracking_status.dart';
import 'local_workspace_test.dart' show MemoryWorkspace;
import 'trackyu_integration_test.dart' show Adapter, MemoryVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final stale in [false, true]) {
    testWidgets(
      stale
          ? 'old position is labelled last known rather than current'
          : 'offline current marker is clear and refresh requests native GPS',
      (tester) async {
        DutyTracker.platformOverride = true;
        addTearDown(() => DutyTracker.platformOverride = null);
        var refreshes = 0, requests = 0;
        final captured = DateTime.now().toUtc().subtract(
          Duration(minutes: stale ? 10 : 0),
        );
        Json point() => {
          'latitude': 23.18,
          'longitude': refreshes > 0 ? 77.43 : 77.42,
          'accuracyMeters': 10,
          'capturedAtUtc': captured.toIso8601String(),
          'attendanceId': 1,
        };
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(DutyTracker.channel, (call) async {
          if (call.method == 'status') {
            return {
              'userId': 'worker',
              'baseUrl': 'https://test.example/api',
              'active': true,
              'gpsEnabled': true,
              'precisePermission': true,
              'lastPoint': point(),
            };
          }
          if (call.method == 'route') {
            expect(
              (call.arguments as Map)['baseUrl'],
              'https://test.example/api',
            );
            return [point()];
          }
          if (call.method == 'refreshFix') {
            expect((call.arguments as Map)['userId'], 'worker');
            refreshes++;
            return null;
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(DutyTracker.channel, null),
        );
        final dio = Dio()
          ..httpClientAdapter = Adapter((r) {
            requests++;
            throw StateError('No server read for current position');
          });
        final c =
            TrackyuController(
                TrackyuApi('https://test.example/api', client: dio),
                vault: MemoryVault(),
              )
              ..local = MemoryWorkspace()
              ..user = {'userId': 'worker'}
              ..offline = true
              ..attendance = {
                'id': 1,
                'punchInUtc': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(minutes: 20))
                    .toIso8601String(),
              };
        await tester.pumpWidget(
          MaterialApp(home: DutyRoutePage(controller: c)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(stale ? 'Last known location' : 'You are here'),
          findsNWidgets(2),
        );
        expect(
          tester
              .widget<CircleLayer>(find.byType(CircleLayer))
              .circles
              .single
              .radius,
          10,
        );
        if (!stale) {
          await tester.tap(find.byTooltip('Refresh GPS'));
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
          expect(refreshes, 1);
          final marker = tester
              .widget<MarkerLayer>(find.byType(MarkerLayer))
              .markers
              .singleWhere(
                (m) => m.key == const ValueKey('user-location-marker'),
              );
          expect(marker.point.longitude, 77.43);
          expect(marker.rotate, true);
          c.user = {'userId': 'different-worker'};
          c.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.text('You are here'), findsNothing);
          expect(find.textContaining('Session changed.'), findsOneWidget);
        }
        expect(requests, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
