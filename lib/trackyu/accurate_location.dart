import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'api.dart';

/// A precise-location permission does not guarantee that the first GPS fix is accurate.
/// Wait for a fresh fix that satisfies the same 50 m limit enforced by the API.
Future<Position> accurateLocation({
  required Future<Position> Function() current,
  required Stream<Position> Function() updates,
  Duration wait = const Duration(seconds: 10),
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  bool usable(Position p) {
    if (p.isMocked) {
      throw const ApiFailure(
        'MOCK_LOCATION',
        'Turn off mock location before marking attendance.',
      );
    }
    return p.latitude.isFinite &&
        p.longitude.isFinite &&
        p.latitude.abs() <= 90 &&
        p.longitude.abs() <= 180 &&
        p.accuracy.isFinite &&
        p.accuracy >= 0 &&
        p.accuracy <= 50 &&
        now().toUtc().difference(p.timestamp.toUtc()) <=
            const Duration(seconds: 180) &&
        p.timestamp.toUtc().difference(now().toUtc()) <=
            const Duration(seconds: 30);
  }

  // Fast-path: Check cached position first for instantaneous (<100ms) location
  try {
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null && usable(lastKnown)) {
      return lastKnown;
    }
  } catch (_) {}

  Position first;
  try {
    first = await current().timeout(wait);
  } on TimeoutException {
    throw const ApiFailure(
      'GPS_TIMEOUT',
      'GPS is taking too long. Move near a window or outdoors and retry.',
    );
  }
  if (usable(first)) return first;
  final result = Completer<Position>();
  final subscription = updates().listen(
    (p) {
      if (result.isCompleted) return;
      try {
        if (usable(p)) result.complete(p);
      } on ApiFailure catch (e) {
        result.completeError(e);
      }
    },
    onError: (Object _, StackTrace __) {
      if (!result.isCompleted) {
        result.completeError(
          const ApiFailure(
            'GPS_UNAVAILABLE',
            'GPS could not get a fresh location. Check location services and retry.',
          ),
        );
      }
    },
    onDone: () {
      if (!result.isCompleted) {
        result.completeError(
          const ApiFailure(
            'LOCATION_INACCURATE',
            'A precise GPS fix is not available yet. Enable precise location and move near a window or outdoors.',
          ),
        );
      }
    },
  );
  try {
    return await result.future.timeout(
      wait,
      onTimeout: () => throw const ApiFailure(
        'LOCATION_INACCURATE',
        'GPS accuracy must be within 50 metres. Enable precise location, move near a window or outdoors, and retry.',
      ),
    );
  } finally {
    await subscription.cancel();
  }
}
