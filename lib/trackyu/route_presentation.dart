import 'package:latlong2/latlong.dart';
import 'api.dart';

double? toNum(dynamic val) {
  final parsed = val is num
      ? val.toDouble()
      : val is String
      ? double.tryParse(val)
      : null;
  return parsed != null && parsed.isFinite ? parsed : null;
}

/// Bounded preview only: the underlying phone/server records remain unchanged.
List<List<Json>> routePreview(dynamic value, {int maxPoints = 1200}) {
  if (value is! List) return [];
  if (maxPoints < 2) maxPoints = 2;
  final groups = <List<Json>>[];
  for (final item in value) {
    if (item is List) {
      groups.add(
        item
            .whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .where((p) => routeCoordinate(p) != null)
            .toList(),
      );
    } else if (item is Map) {
      final point = Map<String, dynamic>.from(item);
      if (routeCoordinate(point) != null) groups.add([point]);
    }
  }
  final count = groups.fold<int>(0, (n, s) => n + s.length);
  final stride = count <= maxPoints ? 1 : (count / (maxPoints - 1)).ceil();
  var index = 0;
  final result = <List<Json>>[];
  for (final group in groups) {
    final preview = <Json>[];
    for (final p in group) {
      if (index % stride == 0 || index == count - 1) {
        preview.add({...p, if (stride > 1) 'displaySampled': true});
      }
      index++;
    }
    if (preview.isNotEmpty) result.add(preview);
  }
  return result;
}

LatLng? safeLatLng(dynamic latVal, dynamic lngVal) {
  final lat = toNum(latVal);
  final lng = toNum(lngVal);
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat.abs() > 90 ||
      lng.abs() > 180) {
    return null;
  }
  return LatLng(lat, lng);
}

LatLng? routeCoordinate(Json? point) {
  return safeLatLng(
    point?['latitude'] ?? point?['inLatitude'],
    point?['longitude'] ?? point?['inLongitude'],
  );
}

bool isCurrentFix(Json? point, DateTime now, {required bool tracking}) {
  if (!tracking || routeCoordinate(point) == null) return false;
  final captured = DateTime.tryParse('${point?['capturedAtUtc']}');
  final rawAccuracy = point?['accuracyMeters'];
  final accuracy = toNum(rawAccuracy);
  if (captured == null || accuracy == null || accuracy < 0 || accuracy > 50) {
    return false;
  }
  final age = now.toUtc().difference(captured.toUtc());
  return age >= const Duration(seconds: -5) &&
      age <= const Duration(seconds: 60);
}

/// Display grouping only. All original fixes and business events stay in storage.
List<Json> groupLocationStops(List<Json> input, List<Json> points) {
  const distance = Distance();
  final result = <Json>[];
  final sorted = List<Json>.from(input)
    ..sort(
      (a, b) => (DateTime.tryParse('${a['startUtc']}') ?? DateTime.utc(1970))
          .compareTo(
            DateTime.tryParse('${b['startUtc']}') ?? DateTime.utc(1970),
          ),
    );
  for (final original in sorted) {
    final start = DateTime.tryParse('${original['startUtc']}');
    final end = DateTime.tryParse('${original['endUtc']}');
    if (start == null || end == null || end.isBefore(start)) continue;
    final next = Map<String, dynamic>.from(original);
    final previous = result.lastOrNull;
    final a = routeCoordinate(previous), b = routeCoordinate(next);
    final prevEnd = DateTime.tryParse('${previous?['endUtc']}');
    final name = '${next['address'] ?? ''}'.trim().toLowerCase();
    final samePlace = a != null && b != null
        ? distance(a, b) <= 50
        : name.isNotEmpty &&
              name == '${previous?['address'] ?? ''}'.trim().toLowerCase();
    final traveled =
        a != null &&
        prevEnd != null &&
        points.any((p) {
          final at = DateTime.tryParse('${p['capturedAtUtc']}');
          final coordinate = routeCoordinate(p);
          final accuracy = toNum(p['accuracyMeters']);
          if (at == null ||
              !at.isAfter(prevEnd) ||
              !at.isBefore(start) ||
              coordinate == null) {
            return false;
          }
          final distFromA = distance(a, coordinate);
          final maxAllowedAccuracy = distFromA > 1000
              ? 500
              : (distFromA > 200 ? 150 : 80);
          return (accuracy == null || accuracy <= maxAllowedAccuracy) &&
              distFromA > 100;
        });
    final prevStart = DateTime.tryParse('${previous?['startUtc']}');
    if (previous != null &&
        prevEnd != null &&
        prevStart != null &&
        samePlace &&
        previous['attendanceId'] == next['attendanceId'] &&
        previous['mode'] == next['mode'] &&
        !traveled &&
        !start.isBefore(prevStart)) {
      final rawPeriods = previous['periods'];
      final periods = rawPeriods is List
          ? rawPeriods
                .whereType<Map>()
                .map((p) => Map<String, dynamic>.from(p))
                .toList()
          : <Json>[];
      final last = periods.lastOrNull;
      final lastEnd = DateTime.tryParse('${last?['endUtc']}');
      if (last != null && lastEnd != null) {
        if (!start.isAfter(lastEnd)) {
          if (end.isAfter(lastEnd)) {
            last['endUtc'] = end.toUtc().toIso8601String();
          }
        } else {
          periods.add({
            'startUtc': original['startUtc'],
            'endUtc': original['endUtc'],
          });
        }
      } else {
        periods.add({
          'startUtc': original['startUtc'],
          'endUtc': original['endUtc'],
        });
      }
      previous['periods'] = periods;
      if (end.isAfter(prevEnd)) previous['endUtc'] = original['endUtc'];
      previous['stoppedSeconds'] = periods.fold<int>(0, (sum, p) {
        final pEnd = DateTime.tryParse('${p['endUtc']}');
        final pStart = DateTime.tryParse('${p['startUtc']}');
        return sum +
            (pEnd != null && pStart != null
                ? pEnd.difference(pStart).inSeconds
                : 0);
      });
    } else {
      next['periods'] = <Json>[
        {'startUtc': original['startUtc'], 'endUtc': original['endUtc']},
      ];
      next['stoppedSeconds'] = end.difference(start).inSeconds;
      result.add(next);
    }
  }
  return result;
}

List<Json> uniqueRouteEvents(List<Json> rows, String idKey, String timeKey) {
  final unique = <String, Json>{};
  for (final row in rows) {
    final key =
        '${row['type'] ?? ''}:${row['requestId'] ?? row[idKey] ?? '${row[timeKey]}:${row['latitude']}:${row['longitude']}:${row['shopName']}'}';
    final previous = unique[key];
    if (previous == null ||
        (previous['checkOutUtc'] == null && row['checkOutUtc'] != null)) {
      unique[key] = row;
    }
  }
  return unique.values.toList();
}

List<List<Json>> groupMapLocations(List<Json> rows) {
  const distance = Distance();
  final groups = <List<Json>>[];
  for (final row in rows) {
    final point = routeCoordinate(row);
    if (point == null) continue;
    final group = groups.where((g) {
      final firstPt = routeCoordinate(g.first);
      return firstPt != null && distance(firstPt, point) <= 25;
    }).firstOrNull;
    if (group == null) {
      groups.add([row]);
    } else {
      group.add(row);
    }
  }
  return groups;
}
