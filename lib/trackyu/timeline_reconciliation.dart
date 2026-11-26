import 'api.dart';
import 'route_presentation.dart';
import 'package:latlong2/latlong.dart';

const businessOffset = Duration(minutes: 330);

DateTime toIST(DateTime dt) {
  if (!dt.isUtc) return dt;
  final ist = dt.add(businessOffset);
  return DateTime(
    ist.year,
    ist.month,
    ist.day,
    ist.hour,
    ist.minute,
    ist.second,
    ist.millisecond,
  );
}

String businessDay(DateTime utc) =>
    utc.toUtc().add(businessOffset).toIso8601String().substring(0, 10);

DateTime? instant(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  // Timestamp contracts are UTC/offset-bearing. Never interpret a naive time in the device zone.
  if (!RegExp(r'(Z|[+-]\d\d:\d\d)$', caseSensitive: false).hasMatch(text)) {
    return null;
  }
  return DateTime.tryParse(text)?.toUtc();
}

DateTime businessDisplay(DateTime utc) => toIST(utc);
String coordinateKey(Json? row) {
  final p = routeCoordinate(row);
  return p == null
      ? ''
      : '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
}

List<Json> rowsOf(dynamic value) =>
    (value is List
            ? value
            : value is Map
            ? value['rows']
            : null)
        is List
    ? ((value is List ? value : value['rows']) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
    : [];
bool rowBelongs(Json row, String owner, String baseUrl) =>
    (row['userId'] == null ||
        '${row['userId']}'.toLowerCase() == owner.toLowerCase()) &&
    (row['baseUrl'] == null || row['baseUrl'] == baseUrl);

Set<String> _visitIds(Json row) => {
  if (row['requestId'] != null) 'request:${row['requestId']}',
  for (final key in ['id', 'localId', 'serverId'])
    if (row[key] != null) 'id:${row[key]}',
};
Json mergeRich(Json older, Json newer) {
  final merged = <String, dynamic>{...older};
  for (final entry in newer.entries) {
    if (entry.value != null && entry.value != '') {
      merged[entry.key] = entry.value;
    }
  }
  // Checkout is monotonic: an older open copy must never reopen a finished local record.
  for (final key in ['checkOutUtc', 'punchOutUtc']) {
    if (older[key] != null && older[key] != '' && (newer[key] == null || newer[key] == '')) merged[key] = older[key];
  }
  return merged;
}

Json? reconcileAttendance(Json? older, Json? newer) {
  if (older == null) return newer;
  if (newer == null) return older;
  final inA = older['punchInUtc'] ?? older['PunchInUtc'];
  final inB = newer['punchInUtc'] ?? newer['PunchInUtc'];
  final a = instant(inA), b = instant(inB);
  final same = a != null && b != null
      ? a == b
      : [older['id'], older['localId'], older['serverId']]
            .where((v) => v != null)
            .any(
              (v) => [
                newer['id'],
                newer['localId'],
                newer['serverId'],
              ].contains(v),
            );
  if (!same) return a != null && (b == null || a.isAfter(b)) ? older : newer;
  return mergeRich(older, newer);
}

bool visitOnDay(Json row, String day) {
  final at = instant(row['checkInUtc']);
  if (at != null) return businessDay(at) == day;
  if (row['checkInUtc'] != null) return false;
  final declared = '${row['workDate'] ?? ''}';
  return RegExp(r'^\d{4}-\d{2}-\d{2}($|T)').hasMatch(declared) &&
      declared.substring(0, 10) == day;
}

List<Json> reconcileVisits(
  Iterable<Json> sources,
  Iterable<Json> pending,
  String day,
  String owner,
  String baseUrl,
) {
  final merged = <Json>[];
  void add(Json row) {
    if (!rowBelongs(row, owner, baseUrl)) return;
    final ids = _visitIds(row);
    final indices = <int>[];
    for (var i = 0; i < merged.length; i++) {
      if (ids.isNotEmpty && _visitIds(merged[i]).intersection(ids).isNotEmpty) {
        indices.add(i);
        ids.addAll(_visitIds(merged[i]));
      }
    }
    if (indices.isEmpty) {
      merged.add({...row});
      return;
    }
    var value = merged[indices.first];
    for (final i in indices.skip(1)) {
      value = mergeRich(value, merged[i]);
    }
    value = mergeRich(value, row);
    for (final i in indices.reversed) {
      merged.removeAt(i);
    }
    merged.add(value);
  }

  for (final row in sources) {
    add(row);
  }
  for (final op in pending) {
    // Legacy unowned queues must not be attributed to whichever account signs in next.
    if (op['scope'] != '$baseUrl|$owner') continue;
    final body = op['body'];
    if (body is! Map) continue;
    final b = Map<String, dynamic>.from(body);
    final at = instant(b['capturedAtUtc']);
    if (at == null) continue;
    final finish = op['finish'] == true || '${op['route']}'.endsWith('/finish');
    if (finish) {
      final target = merged
          .where((r) => _visitIds(r).contains('id:${b['id'] ?? op['localId']}'))
          .firstOrNull;
      if (target != null) {
        add({
          ...target,
          ...b,
          'requestId': target['requestId'],
          'checkInUtc': target['checkInUtc'],
          'checkOutUtc': at.toIso8601String(),
        });
      }
    } else {
      add({
        ...b,
        if (op['localId'] != null) 'localId': op['localId'],
        'checkInUtc': at.toIso8601String(),
      });
    }
  }
  return merged.where((r) => visitOnDay(r, day)).toList()
    ..sort((a, b) => '${a['checkInUtc']}'.compareTo('${b['checkInUtc']}'));
}

List<Json> mergePoints(
  Iterable<Json> points,
  String day,
  String owner,
  String baseUrl,
) {
  final byId = <String, Json>{};
  final byFix = <String, String>{};
  for (final original in points) {
    if (!rowBelongs(original, owner, baseUrl)) continue;
    final at = instant(original['capturedAtUtc']);
    if (at == null ||
        businessDay(at) != day ||
        routeCoordinate(original) == null) {
      continue;
    }
    final p = {
      ...original,
      'mode': original['mode'] ?? original['attendanceMode'],
      'capturedAtUtc': at.toIso8601String(),
    };
    final fix =
        '${p['mode']}:${p['attendanceId']}:${at.microsecondsSinceEpoch}:${p['latitude']}:${p['longitude']}';
    final id = '${p['sampleId'] ?? p['id'] ?? fix}';
    final key = byFix[fix] ?? id;
    byFix[fix] = key;
    byId[key] = byId[key] == null ? p : mergeRich(byId[key]!, p);
  }
  return byId.values.toList()..sort(
    (a, b) =>
        instant(a['capturedAtUtc'])!.compareTo(instant(b['capturedAtUtc'])!),
  );
}

bool connectedFixes(Json a, Json b) {
  final from = instant(a['capturedAtUtc']), to = instant(b['capturedAtUtc']);
  final p = routeCoordinate(a), q = routeCoordinate(b);
  if (from == null || to == null || p == null || q == null) return false;
  final seconds = to.difference(from).inMilliseconds / 1000;
  // Allow continuous travel during shift up to 1 hour gap between fixes
  if (seconds <= 0 ||
      seconds > 300 ||
      a['attendanceId'] != b['attendanceId'] ||
      (a['mode'] ?? a['attendanceMode']) !=
          (b['mode'] ?? b['attendanceMode']) ||
      a['displaySampled'] == true ||
      b['displaySampled'] == true ||
      b['breakBefore'] == true) {
    return false;
  }
  final meters = const Distance()(p, q);
  // Speed check: ignore unrealistic teleportation > 162 km/h (45 m/s)
  return !(meters > 100 && meters / seconds > 45);
}

List<List<Json>> recordedSegments(List<Json> points) {
  final result = <List<Json>>[];
  Json? previous;
  for (final point in points) {
    final accuracy = toNum(point['accuracyMeters']);
    // Accept moving GPS fixes up to 100m accuracy so road/vehicle movement is never dropped
    if (accuracy == null ||
        accuracy > 100 ||
        accuracy < 0 ||
        point['isAccurate'] == false) {
      previous = null;
      continue;
    }
    final boundary = previous == null || !connectedFixes(previous, point);
    if (boundary) result.add([]);
    result.last.add({...point, if (boundary) 'breakBefore': true});
    previous = point;
  }
  return result;
}

List<Json> recordingGaps(List<List<Json>> segments) {
  final gaps = <Json>[];
  for (var i = 1; i < segments.length; i++) {
    final a = segments[i - 1].last, b = segments[i].first;
    final start = instant(a['capturedAtUtc']),
        end = instant(b['capturedAtUtc']);
    if (start == null || end == null || !end.isAfter(start)) continue;

    final p = routeCoordinate(a), q = routeCoordinate(b);
    final meters = (p != null && q != null) ? const Distance()(p, q) : null;
    final diffSec = end.difference(start).inSeconds;

    if (diffSec < 120 && (meters == null || meters < 25)) {
      continue;
    }

    final isStationary = meters != null && meters < 75;

    gaps.add({
      'startUtc': start.toIso8601String(),
      'endUtc': end.toIso8601String(),
      'reason': isStationary
          ? 'Halt / Stationary'
          : (diffSec > 1800 ? 'GPS interval (>30 min)' : 'Between GPS fixes'),
      'isStationary': isStationary,
      'latitude': a['latitude'] ?? b['latitude'],
      'longitude': a['longitude'] ?? b['longitude'],
      'endLatitude': b['latitude'],
      'endLongitude': b['longitude'],
      'distanceMeters': meters,
      'address': a['address'] ?? b['address'],
      'fromPoint': a,
      'toPoint': b,
    });
  }
  final coalesced = <Json>[];
  for (final gap in gaps) {
    if (coalesced.isNotEmpty &&
        coalesced.last['isStationary'] == true &&
        gap['isStationary'] == true) {
      final prev = coalesced.last;
      final prevLat = toNum(prev['latitude']);
      final prevLng = toNum(prev['longitude']);
      final currLat = toNum(gap['latitude']);
      final currLng = toNum(gap['longitude']);
      if (prevLat != null && prevLng != null && currLat != null && currLng != null) {
        final dist = const Distance()(
            LatLng(prevLat.toDouble(), prevLng.toDouble()),
            LatLng(currLat.toDouble(), currLng.toDouble()));
        if (dist <= 100) {
          prev['endUtc'] = gap['endUtc'];
          prev['endLatitude'] = gap['endLatitude'];
          prev['endLongitude'] = gap['endLongitude'];
          prev['address'] ??= gap['address'];
          continue;
        }
      }
    }
    coalesced.add(Map<String, dynamic>.from(gap));
  }
  return coalesced;
}
List<Json> detectedStops(List<List<Json>> segments) {
  final stops = <Json>[];
  const distCalc = Distance();
  for (final segment in segments) {
    if (segment.isEmpty) continue;
    Json? first, last;
    var count = 0;
    LatLng? anchor;

    void finish() {
      if (first != null &&
          last != null &&
          count >= 2 &&
          instant(last!['capturedAtUtc'])!
                  .difference(instant(first!['capturedAtUtc'])!)
                  .inMinutes >= 8) {
        stops.add({
          'startUtc': first!['capturedAtUtc'],
          'endUtc': last!['capturedAtUtc'],
          'latitude': anchor?.latitude ?? first!['latitude'],
          'longitude': anchor?.longitude ?? first!['longitude'],
          'attendanceId': first!['attendanceId'],
          'mode': first!['mode'],
          'sampleCount': count,
        });
      }
      first = null;
      last = null;
      anchor = null;
      count = 0;
    }

    for (final p in segment) {
      final pCoord = routeCoordinate(p);
      final pTime = instant(p['capturedAtUtc']);
      if (pCoord == null || pTime == null) continue;

      if (anchor == null) {
        first = p;
        last = p;
        anchor = pCoord;
        count = 1;
        continue;
      }

      final currentAnchor = anchor!;
      final d = distCalc(currentAnchor, pCoord);
      // Indoors, GPS points jitter up to 85m. Centroid-smoothed bubble keeps stay intact.
      if (d > 85.0) {
        finish();
        first = p;
        last = p;
        anchor = pCoord;
        count = 1;
      } else {
        last = p;
        count++;
        anchor = LatLng(
          currentAnchor.latitude * 0.8 + pCoord.latitude * 0.2,
          currentAnchor.longitude * 0.8 + pCoord.longitude * 0.2,
        );
      }
    }
    finish();
  }
  return groupLocationStops(stops, segments.expand((s) => s).toList());
}

double pathDistance(List<Json> points) {
  if (points.length < 2) return 0.0;
  const distCalc = Distance();
  var sum = 0.0;
  LatLng? anchor = routeCoordinate(points.first);
  DateTime? anchorTime = instant(points.first['capturedAtUtc']);

  for (var i = 1; i < points.length; i++) {
    final curr = points[i];
    final currCoord = routeCoordinate(curr);
    final currTime = instant(curr['capturedAtUtc']);
    if (currCoord == null) continue;

    if (anchor == null) {
      anchor = currCoord;
      anchorTime = currTime;
      continue;
    }

    final moved = distCalc(anchor, currCoord);
    final acc = toNum(curr['accuracyMeters']) ?? 20.0;
    final threshold = (acc > 25.0 ? acc : 25.0).clamp(20.0, 45.0);

    if (moved >= threshold) {
      if (anchorTime != null && currTime != null) {
        final dtSec = currTime.difference(anchorTime).inSeconds.abs();
        if (dtSec > 0 && (moved / dtSec) > 33.3) {
          anchor = currCoord;
          anchorTime = currTime;
          continue;
        }
      }
      sum += moved;
      anchor = currCoord;
      anchorTime = currTime;
    }
  }
  return sum;
}

double recordedDistance(List<List<Json>> segments) {
  var sum = 0.0;
  for (final segment in segments) {
    if (segment.length < 2) continue;
    final legs = extractMovingLegs(segment);
    if (legs.isNotEmpty) {
      for (final leg in legs) {
        sum += leg.distanceMeters;
      }
    } else {
      final fallback = evaluateMovingLeg(segment);
      if (fallback != null) {
        sum += fallback.distanceMeters;
      }
    }
  }
  return sum;
}


class MovingLeg {
  final List<Json> points;
  final DateTime startUtc;
  final DateTime endUtc;
  final double distanceMeters;
  final double netDisplacement;
  final double avgSpeedKmh;

  MovingLeg({
    required this.points,
    required this.startUtc,
    required this.endUtc,
    required this.distanceMeters,
    required this.netDisplacement,
    required this.avgSpeedKmh,
  });
}

List<MovingLeg> extractMovingLegs(List<Json> segment) {
  if (segment.length < 2) return [];
  const distCalc = Distance();

  // 1. Identify all stationary ranges [startIdx, endIdx] in this segment
  // A range is stationary if points cluster within 75m of a centroid anchor
  // for at least 4 minutes (240s), preventing indoor drift from resetting the anchor.
  final stationaryRanges = <List<int>>[];
  int anchorIdx = 0;
  LatLng? anchorCoord = routeCoordinate(segment[0]);
  DateTime? anchorTime = instant(segment[0]['capturedAtUtc']);

  for (int i = 1; i < segment.length; i++) {
    final ptCoord = routeCoordinate(segment[i]);
    final ptTime = instant(segment[i]['capturedAtUtc']);
    if (ptCoord == null || ptTime == null || anchorCoord == null || anchorTime == null) continue;

    final distFromAnchor = distCalc(anchorCoord, ptCoord);
    if (distFromAnchor <= 75.0) {
      // Centroid smoothing stabilizes anchor against indoor GPS jitter
      anchorCoord = LatLng(
        anchorCoord.latitude * 0.85 + ptCoord.latitude * 0.15,
        anchorCoord.longitude * 0.85 + ptCoord.longitude * 0.15,
      );
    } else {
      final durSec = ptTime.difference(anchorTime).inSeconds;
      if (durSec >= 240 && (i - 1 - anchorIdx) >= 2) {
        stationaryRanges.add([anchorIdx, i - 1]);
      }
      anchorIdx = i;
      anchorCoord = ptCoord;
      anchorTime = ptTime;
    }
  }

  if (anchorTime != null) {
    final lastTime = instant(segment.last['capturedAtUtc']);
    if (lastTime != null) {
      final durSec = lastTime.difference(anchorTime).inSeconds;
      if (durSec >= 240 && (segment.length - 1 - anchorIdx) >= 2) {
        stationaryRanges.add([anchorIdx, segment.length - 1]);
      }
    }
  }

  // 2. The intervals between stationary ranges are candidate moving legs
  final movingLegs = <MovingLeg>[];
  int curStartIdx = 0;

  for (final stRange in stationaryRanges) {
    final stStart = stRange[0];
    final stEnd = stRange[1];

    if (stStart > curStartIdx) {
      final sub = segment.sublist(curStartIdx, stStart + 1);
      final leg = evaluateMovingLeg(sub);
      if (leg != null) movingLegs.add(leg);
    }
    curStartIdx = stEnd;
  }

  if (curStartIdx < segment.length - 1) {
    final sub = segment.sublist(curStartIdx);
    final leg = evaluateMovingLeg(sub);
    if (leg != null) movingLegs.add(leg);
  }

  return movingLegs;
}

MovingLeg? evaluateMovingLeg(List<Json> rawPoints) {
  if (rawPoints.length < 2) return null;
  const distCalc = Distance();

  // Trim leading stationary dwell (points before actual departure on the road)
  var startIdx = 0;
  while (startIdx < rawPoints.length - 1) {
    final pCur = routeCoordinate(rawPoints[startIdx]);
    final pNext = routeCoordinate(rawPoints[startIdx + 1]);
    final tCur = instant(rawPoints[startIdx]['capturedAtUtc']);
    final tNext = instant(rawPoints[startIdx + 1]['capturedAtUtc']);
    if (pCur != null && pNext != null && tCur != null && tNext != null) {
      final gapSec = tNext.difference(tCur).inSeconds;
      final d = distCalc(pCur, pNext);
      if (gapSec >= 180 && d < 120.0) {
        startIdx++;
        continue;
      }
    }
    break;
  }

  // Trim trailing stationary dwell (points after arrival at destination)
  var endIdx = rawPoints.length - 1;
  while (endIdx > startIdx) {
    final pCur = routeCoordinate(rawPoints[endIdx]);
    final pPrev = routeCoordinate(rawPoints[endIdx - 1]);
    final tCur = instant(rawPoints[endIdx]['capturedAtUtc']);
    final tPrev = instant(rawPoints[endIdx - 1]['capturedAtUtc']);
    if (pCur != null && pPrev != null && tCur != null && tPrev != null) {
      final gapSec = tCur.difference(tPrev).inSeconds;
      final d = distCalc(pCur, pPrev);
      if (gapSec >= 180 && d < 120.0) {
        endIdx--;
        continue;
      }
    }
    break;
  }

  final points = rawPoints.sublist(startIdx, endIdx + 1);
  if (points.length < 2) return null;

  final pFirst = routeCoordinate(points.first);
  final pLast = routeCoordinate(points.last);
  if (pFirst == null || pLast == null) return null;

  final startUtc = instant(points.first['capturedAtUtc']);
  final endUtc = instant(points.last['capturedAtUtc']);
  if (startUtc == null || endUtc == null || !endUtc.isAfter(startUtc)) return null;

  final durSec = endUtc.difference(startUtc).inSeconds;
  // Discard sub-minute twitches/glitches (like the 0 min 588m glitch)
  if (durSec < 60) return null;

  final dist = pathDistance(points);
  if (dist < 120.0) return null;

  final netDisplacement = distCalc(pFirst, pLast);
  // Real transit requires meaningful net displacement
  if (netDisplacement < 90.0 && dist < 250.0) return null;

  final speedKmh = durSec > 0 ? (dist / 1000.0) / (durSec / 3600.0) : 0.0;
  if (speedKmh > 120.0) return null; // Glitch spike > 120 km/h

  return MovingLeg(
    points: points,
    startUtc: startUtc,
    endUtc: endUtc,
    distanceMeters: dist,
    netDisplacement: netDisplacement,
    avgSpeedKmh: speedKmh,
  );
}

List<Json> attendanceEvents(Iterable<Json> attendances, String day) {
  final result = <String, Json>{};
  for (final a in attendances) {
    for (final out in [false, true]) {
      final at = instant(a[out ? 'punchOutUtc' : 'punchInUtc']);
      if (at == null || businessDay(at) != day) continue;
      final type = out ? 'PunchOut' : 'PunchIn';
      final key = '$type:${at.toIso8601String()}';
      result[key] = {
        'id': key,
        'type': type,
        'title': out ? 'Punch-out' : 'Punch-in',
        'atUtc': at.toIso8601String(),
        'latitude': a[out ? 'outLatitude' : 'inLatitude'],
        'longitude': a[out ? 'outLongitude' : 'inLongitude'],
      };
    }
  }
  return result.values.toList();
}

List<Json> dayEvents(Iterable<Json> events, String day) {
  final result = <String, Json>{};
  for (final row in events) {
    final at = instant(row['atUtc']);
    if (at == null || businessDay(at) != day) continue;
    final key = '${row['type']}:${at.toIso8601String()}';
    result[key] = result[key] == null ? {...row} : mergeRich(result[key]!, row);
  }
  return result.values.toList()
    ..sort((a, b) => '${a['atUtc']}'.compareTo('${b['atUtc']}'));
}
