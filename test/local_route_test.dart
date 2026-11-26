import 'package:fieldforce_hrms/trackyu/timeline_reconciliation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/tracking_status.dart';
import 'trackyu_integration_test.dart' show Adapter, MemoryVault;
import 'local_workspace_test.dart' show MemoryWorkspace;

void main() {
  testWidgets(
    'coarse GPS stays visible but gaps do not create a seven kilometre recorded route',
    (tester) async {
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = Adapter((r) {
          requests++;
          throw StateError('Route must read phone data');
        });
      final c =
          TrackyuController(
              TrackyuApi('https://test.example/api', client: dio),
              vault: MemoryVault(),
            )
            ..offline = true
            ..local = MemoryWorkspace({
              'events': [],
              'visits': [],
              'route': {
                'distanceMeters': 0,
                'segments': [
                  [
                    {
                      'latitude': 23.18,
                      'longitude': 77.42,
                      'capturedAtUtc':
                          '${businessDay(DateTime.now())}T08:00:00Z',
                      'accuracyMeters': 10,
                    },
                    {
                      'latitude': 23.181,
                      'longitude': 77.421,
                      'capturedAtUtc':
                          '${businessDay(DateTime.now())}T08:01:00Z',
                      'accuracyMeters': 10,
                    },
                    {
                      'latitude': 23.23,
                      'longitude': 77.48,
                      'capturedAtUtc':
                          '${businessDay(DateTime.now())}T08:15:00Z',
                      'accuracyMeters': 80,
                    },
                  ],
                ],
                'stops': [
                  {
                    'latitude': 23.18,
                    'longitude': 77.42,
                    'startUtc': '${businessDay(DateTime.now())}T08:00:00Z',
                    'endUtc': '${businessDay(DateTime.now())}T08:30:00Z',
                    'address': 'Start area',
                  },
                ],
              },
            });
      await tester.pumpWidget(MaterialApp(home: DutyRoutePage(controller: c)));
      await tester.pumpAndSettle();
      final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(
        layer.polylines
            .expand((p) => p.points)
            .any((p) => p.latitude == 23.23 && p.longitude == 77.48),
        false,
      );
      final circles = tester
          .widget<CircleLayer>(find.byType(CircleLayer))
          .circles;
      expect(circles.any((c) => c.point.latitude == 23.23), true);
      expect(requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
