import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/gps_radar_loader.dart';

void main() {
  testWidgets('GPS loader is animation only even when callers provide labels', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: SizedBox(
      width: 180, child: GpsRadarLoader(label: 'Locking GPS Coordinates', sublabel: 'Acquiring satellite fix'))))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
