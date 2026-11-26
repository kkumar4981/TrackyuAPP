import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/accurate_location.dart';

Position fix(double accuracy, {DateTime? at, bool mocked = false}) => Position(
  latitude: 19.076,
  longitude: 72.8777,
  timestamp: at ?? DateTime.now().toUtc(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 0,
  speedAccuracy: 1,
  isMocked: mocked,
);
void main() {
  test('an accurate first fix needs no GPS stream', () async {
    var streams = 0;
    final result = await accurateLocation(
      current: () async => fix(50),
      updates: () {
        streams++;
        return const Stream.empty();
      },
    );
    expect(result.accuracy, 50);
    expect(streams, 0);
  });
  test(
    'a coarse first fix waits for an accurate update and cancels the sensor',
    () async {
      var cancelled = 0;
      final sensor = StreamController<Position>(onCancel: () => cancelled++);
      final pending = accurateLocation(
        current: () async => fix(180),
        updates: () => sensor.stream,
      );
      await Future<void>.delayed(Duration.zero);
      sensor.add(fix(90));
      sensor.add(fix(12));
      expect((await pending).accuracy, 12);
      expect(cancelled, 1);
      await sensor.close();
    },
  );
  test(
    'stale GPS does not count as a fresh fix even if accuracy looks good',
    () async {
      final now = DateTime.now().toUtc();
      final result = await accurateLocation(
        current: () async =>
            fix(5, at: now.subtract(const Duration(minutes: 4))),
        updates: () => Stream.fromIterable([fix(8, at: now)]),
        clock: () => now,
      );
      expect(result.accuracy, 8);
    },
  );
  test(
    'waiting for better GPS times out with a useful message and closes stream',
    () async {
      var cancelled = 0;
      final sensor = StreamController<Position>(onCancel: () => cancelled++);
      await expectLater(
        accurateLocation(
          current: () async => fix(800),
          updates: () => sensor.stream,
          wait: const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.code, 'code', 'LOCATION_INACCURATE')
              .having((e) => e.message, 'message', contains('50 metres')),
        ),
      );
      expect(cancelled, 1);
      await sensor.close();
    },
  );
  test('mock GPS is rejected even when it claims excellent accuracy', () async {
    await expectLater(
      accurateLocation(
        current: () async => fix(1, mocked: true),
        updates: () => const Stream.empty(),
      ),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'MOCK_LOCATION')),
    );
  });
  test(
    'GPS update failure is a clear error rather than an invalid attendance write',
    () async {
      await expectLater(
        accurateLocation(
          current: () async => fix(100),
          updates: () => Stream.error(StateError('sensor unavailable')),
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'GPS_UNAVAILABLE'),
        ),
      );
    },
  );
  test(
    'field validation responses expose action without echoing payload or credentials',
    () {
      expect(
        TrackyuApi.validationMessage({
          'errorCode': 'VALIDATION_ERROR',
          'errors': {
            'AccuracyMeters': ['Invalid or missing value.'],
          },
        }),
        contains('GPS'),
      );
      expect(
        TrackyuApi.validationMessage({
          'errorCode': 'VALIDATION_ERROR',
          'errors': {
            'attendanceId': ['Invalid'],
          },
        })?.toLowerCase(),
        contains('reload attendance'),
      );
      expect(
        TrackyuApi.validationMessage({
          'errorCode': 'VALIDATION_ERROR',
          'errors': {
            'userPassword': ['private-value'],
          },
        }),
        isNull,
      );
    },
  );
}
