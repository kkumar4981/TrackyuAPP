import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:fieldforce_hrms/trackyu/punch_telemetry.dart';

void main() {
  test(
    'battery zero, legacy phone description and city use the same GPS fix',
    () async {
      final collector = PunchTelemetryCollector(
        battery: () async => 0,
        device: () async => 'B : Oppo ,M : Test ,OSVer : 16',
        geocode: (lat, lng) async {
          expect(lat, 19.076);
          expect(lng, 77.42545440);
          return [
            const Placemark(
              locality: 'Test city',
              street: 'Test street',
              administrativeArea: 'Test state',
              country: 'India',
            ),
          ];
        },
      );
      final result = await collector.collect(19.076, 77.42545440);
      expect(result['batteryPercent'], 0);
      expect(result['deviceInfo'], contains('Oppo'));
      expect(result['city'], 'Test city');
      expect(result['address'], contains('Test street'));
    },
  );
  test(
    'unavailable or invalid telemetry stays unknown instead of fake defaults',
    () async {
      final collector = PunchTelemetryCollector(
        battery: () async => -1,
        device: () async => throw StateError('device unavailable'),
        geocode: (_, _) async => throw StateError('geocoder unavailable'),
      );
      final result = await collector.collect(19, 77);
      expect(result.values.every((v) => v == null), isTrue);
    },
  );
}
