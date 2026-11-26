import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/route_presentation.dart';

void main() {
  final now = DateTime.utc(2026, 11, 9, 12);
  Json point(double lat, double lng, DateTime at, {int accuracy = 10}) => {
    'latitude': lat,
    'longitude': lng,
    'capturedAtUtc': at.toIso8601String(),
    'accuracyMeters': accuracy,
  };
  Json stop(int start, int end, {double lat = 23.18, double lng = 77.42}) => {
    'latitude': lat,
    'longitude': lng,
    'address': 'Same address',
    'startUtc': now.add(Duration(minutes: start)).toIso8601String(),
    'endUtc': now.add(Duration(minutes: end)).toIso8601String(),
  };
  test(
    'repeated same-place readings form one card without counting missing coverage',
    () {
      final raw = [stop(0, 10), stop(20, 30, lat: 23.18001)];
      final grouped = groupLocationStops(raw, []);
      expect(grouped, hasLength(1));
      expect(grouped.single['stoppedSeconds'], 1200);
      expect(grouped.single['periods'], hasLength(2));
      expect(raw.first.containsKey('periods'), false);
    },
  );
  test('overlapping duplicate stops do not double count duration', () {
    final grouped = groupLocationStops([
      stop(0, 10),
      stop(5, 15),
      stop(5, 15),
    ], []);
    expect(grouped, hasLength(1));
    expect(grouped.single['stoppedSeconds'], 900);
  });
  test('leaving and returning is preserved as separate stays', () {
    final grouped = groupLocationStops(
      [stop(0, 10), stop(20, 30)],
      [point(23.22, 77.46, now.add(const Duration(minutes: 15)))],
    );
    expect(grouped, hasLength(2));
    expect(
      groupLocationStops([stop(0, 10), stop(20, 30, lat: 23.25)], []),
      hasLength(2),
    );
  });
  test('current label requires a recent precise fix while tracking', () {
    final fresh = point(23.18, 77.42, now);
    expect(isCurrentFix(fresh, now, tracking: true), true);
    expect(isCurrentFix(fresh, now, tracking: false), false);
    expect(
      isCurrentFix(fresh, now.add(const Duration(minutes: 2)), tracking: true),
      false,
    );
    expect(
      isCurrentFix(
        point(23.18, 77.42, now, accuracy: 200),
        now,
        tracking: true,
      ),
      false,
    );
    expect(
      isCurrentFix(
        point(23.18, 77.42, now.add(const Duration(minutes: 2))),
        now,
        tracking: true,
      ),
      false,
    );
    expect(routeCoordinate({'latitude': double.nan, 'longitude': 77}), isNull);
  });
  test(
    'map clusters repeated coordinates but preserves separate visit records',
    () {
      final rows = [
        {...point(23.18, 77.42, now), 'id': 1},
        {...point(23.18001, 77.42001, now), 'id': 2},
        {...point(23.24, 77.48, now), 'id': 3},
      ];
      final groups = groupMapLocations(rows);
      expect(groups, hasLength(2));
      expect(groups.first.map((p) => p['id']), [1, 2]);
      expect(
        uniqueRouteEvents([rows[0], rows[0], rows[1]], 'id', 'capturedAtUtc'),
        hasLength(2),
      );
    },
  );
  test(
    'dense route preview is bounded and preserves endpoints and originals',
    () {
      final rows = List.generate(
        20000,
        (i) => <String, dynamic>{
          'latitude': 23.0 + i / 1000000,
          'longitude': 77.0,
          'id': i,
        },
      );
      final preview = routePreview([
        rows.take(10000).toList(),
        rows.skip(10000).toList(),
      ]);
      final points = preview.expand((s) => s).toList();
      expect(points.length, lessThanOrEqualTo(1200));
      expect(preview.length, 2);
      expect(points.first['id'], 0);
      expect(points.last['id'], 19999);
      expect(rows.length, 20000);
      expect(rows.first.containsKey('displaySampled'), false);
    },
  );
  test('numeric decoding rejects non-finite values and accepts integers', () {
    expect(toNum(10), 10.0);
    for (final value in ['NaN', 'Infinity', double.infinity, double.nan]) {
      expect(toNum(value), isNull);
    }
  });
}
