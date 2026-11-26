import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/gps_fix_validator.dart';

void main() {
  group('Production GPS Fix Validator (isValidGpsFix)', () {
    final baseTime = DateTime.parse('2026-11-17T12:00:00Z');

    test('accepts valid fresh fix with realistic accuracy', () {
      final valid = isValidGpsFix(
        lat: 19.0760,
        lng: 72.8777,
        acc: 15.0,
        capturedAt: baseTime.subtract(const Duration(seconds: 30)),
        isMocked: false,
        now: baseTime,
      );
      expect(valid, isTrue);
    });

    test('rejects null values for lat, lng, acc, or capturedAt', () {
      expect(isValidGpsFix(lat: null, lng: 72.87, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.07, lng: null, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.07, lng: 72.87, acc: null, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.07, lng: 72.87, acc: 20, capturedAt: null, isMocked: false, now: baseTime), isFalse);
    });

    test('rejects non-finite (NaN, Infinity) coordinates', () {
      expect(isValidGpsFix(lat: double.nan, lng: 72.87, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.07, lng: double.infinity, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.07, lng: 72.87, acc: double.infinity, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
    });

    test('rejects out-of-range latitude and longitude', () {
      expect(isValidGpsFix(lat: 91.0, lng: 72.87, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: -91.0, lng: 72.87, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.07, lng: 181.0, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.07, lng: -181.0, acc: 20, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
    });

    test('rejects Null Island (0.0, 0.0)', () {
      expect(isValidGpsFix(lat: 0.0, lng: 0.0, acc: 10, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
    });

    test('rejects mocked location fixes unconditionally', () {
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 5.0, capturedAt: baseTime, isMocked: true, now: baseTime), isFalse);
    });

    test('rejects accuracy <= 0 or > 500 meters', () {
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 0.0, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: -5.0, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 501.0, capturedAt: baseTime, isMocked: false, now: baseTime), isFalse);
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 500.0, capturedAt: baseTime, isMocked: false, now: baseTime), isTrue);
    });

    test('rejects stale fixes (> 15 minutes / 900s)', () {
      final stale = baseTime.subtract(const Duration(seconds: 901));
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 20.0, capturedAt: stale, isMocked: false, now: baseTime), isFalse);

      final boundary = baseTime.subtract(const Duration(seconds: 900));
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 20.0, capturedAt: boundary, isMocked: false, now: baseTime), isTrue);
    });

    test('rejects future drift exceeding 15 seconds skew', () {
      final excessiveFuture = baseTime.add(const Duration(seconds: 16));
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 20.0, capturedAt: excessiveFuture, isMocked: false, now: baseTime), isFalse);

      final acceptableSkew = baseTime.add(const Duration(seconds: 14));
      expect(isValidGpsFix(lat: 19.0760, lng: 72.8777, acc: 20.0, capturedAt: acceptableSkew, isMocked: false, now: baseTime), isTrue);
    });
  });
}
