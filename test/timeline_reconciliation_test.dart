import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/timeline_reconciliation.dart';
import 'package:fieldforce_hrms/trackyu/route_presentation.dart';

void main() {
  const owner = 'worker', base = 'https://test.example/api', day = '2026-11-10';
  Json p(String time, {String? id, int attendance = 1, double lat = 23.0}) => {
    if (id != null) 'id': id,
    'latitude': lat,
    'longitude': 77.0,
    'accuracyMeters': 5,
    'capturedAtUtc': time,
    'attendanceId': attendance,
    'mode': 'Field',
  };
  test('IST midnight excludes other dates irrespective of device timezone', () {
    expect(businessDay(DateTime.parse('2026-11-09T18:29:59Z')), '2026-11-09');
    final rows = reconcileVisits(
      [
        {'id': 1, 'checkInUtc': '2026-11-09T18:29:59Z', 'workDate': day},
        {'id': 2, 'checkInUtc': '2026-11-09T18:30:00Z'},
        {'id': 3, 'checkInUtc': '2026-11-10T18:30:00Z'},
        {'id': 4},
      ],
      [],
      day,
      owner,
      base,
    );
    expect(rows.map((r) => r['id']), [2]);
    expect(instant('2026-11-10T10:30:00'), isNull);
  });
  test(
    'offline start and finish reconcile once instead of rendering request bodies',
    () {
      final visits = reconcileVisits(
        [],
        [
          {
            'scope': '$base|$owner',
            'finish': false,
            'localId': 100,
            'body': {
              'requestId': 'start-id',
              'shopName': 'Shop',
              'capturedAtUtc': '2026-11-10T04:30:00Z',
            },
          },
          {
            'scope': '$base|$owner',
            'finish': true,
            'body': {
              'id': 100,
              'requestId': 'finish-id',
              'capturedAtUtc': '2026-11-10T05:00:00Z',
              'remark': 'Done',
            },
          },
        ],
        day,
        owner,
        base,
      );
      expect(visits, hasLength(1));
      expect(visits.single['checkInUtc'], '2026-11-10T04:30:00.000Z');
      expect(visits.single['checkOutUtc'], '2026-11-10T05:00:00.000Z');
      expect(visits.single['remark'], 'Done');
    },
  );
  test(
    'stable request/local/server identities preserve checkout and richer fields',
    () {
      final rows = reconcileVisits(
        [
          {
            'id': 100,
            'localId': 100,
            'requestId': 'a',
            'checkInUtc': '2026-11-10T04:30:00Z',
            'checkOutUtc': '2026-11-10T05:00:00Z',
            'address': 'Local address',
          },
          {
            'id': 7,
            'serverId': 7,
            'requestId': 'a',
            'checkInUtc': '2026-11-10T04:30:00Z',
            'checkOutUtc': null,
            'shopName': 'Server shop',
          },
          {
            'id': 7,
            'checkInUtc': '2026-11-10T04:30:00Z',
            'remark': 'Server remark',
          },
        ],
        [],
        day,
        owner,
        base,
      );
      expect(rows, hasLength(1));
      expect(rows.single['checkOutUtc'], '2026-11-10T05:00:00Z');
      expect(rows.single['address'], 'Local address');
      expect(rows.single['remark'], 'Server remark');
    },
  );
  test('foreign workspace and unowned pending items are excluded', () {
    expect(
      reconcileVisits(
        [
          {'id': 1, 'userId': 'other', 'checkInUtc': '2026-11-10T04:30:00Z'},
        ],
        [
          {
            'finish': false,
            'body': {'capturedAtUtc': '2026-11-10T04:30:00Z'},
          },
        ],
        day,
        owner,
        base,
      ),
      isEmpty,
    );
    expect(
      mergePoints(
        [
          {...p('2026-11-10T04:30:00Z'), 'baseUrl': 'https://other/api'},
        ],
        day,
        owner,
        base,
      ),
      isEmpty,
    );
  });
  test(
    'partial local trail augments server history and sample aliases deduplicate',
    () {
      final rows = mergePoints(
        [
          {...p('2026-11-10T04:30:00Z', id: 'a')},
          {
            ...p('2026-11-10T04:31:00Z'),
            'sampleId': 'b',
            'attendanceMode': 'Field',
          },
          p('2026-11-10T04:31:00Z', id: 'b'),
          p('2026-11-10T04:32:00Z', id: 'c'),
        ],
        day,
        owner,
        base,
      );
      expect(rows, hasLength(3));
      expect(rows.first['id'], 'a');
    },
  );
  test(
    'old or untimed fix is never live; reading does not manufacture timestamps',
    () {
      final old = p('2026-11-10T04:30:00Z');
      expect(
        isCurrentFix(
          old,
          DateTime.parse('2026-11-10T05:00:00Z'),
          tracking: true,
        ),
        false,
      );
      expect(
        isCurrentFix(
          {'latitude': 23, 'longitude': 77, 'accuracyMeters': 5},
          DateTime.now(),
          tracking: true,
        ),
        false,
      );
      expect(old['capturedAtUtc'], '2026-11-10T04:30:00Z');
      expect(coordinateKey(old), '23.0000,77.0000');
    },
  );
  test('new local punch-out survives stale open attendance/report', () {
    final merged = reconcileAttendance(
      {
        'id': 1,
        'punchInUtc': '2026-11-10T04:30:00Z',
        'punchOutUtc': '2026-11-10T05:30:00Z',
      },
      {'id': 1, 'punchInUtc': '2026-11-10T04:30:00Z', 'punchOutUtc': null},
    );
    final events = dayEvents([
      {'type': 'PunchIn', 'atUtc': '2026-11-10T04:30:00Z'},
      ...attendanceEvents([merged!], day),
    ], day);
    expect(events, hasLength(2));
    expect(events.last['type'], 'PunchOut');
  });
  test(
    'gaps, impossible jumps and different attendance sessions are never bridged',
    () {
      final rows = mergePoints(
        [
          p('2026-11-10T04:30:00Z', lat: 23),
          p('2026-11-10T04:31:00Z', lat: 23.001),
          p('2026-11-10T06:30:00Z', lat: 24),
          p('2026-11-10T06:31:00Z', lat: 24.001),
          p('2026-11-10T06:32:00Z', lat: 25, attendance: 2),
        ],
        day,
        owner,
        base,
      );
      final segments = recordedSegments(rows);
      expect(segments, hasLength(3));
      expect(recordingGaps(segments), hasLength(2));
      expect(recordedDistance(segments), inInclusiveRange(200, 230));
      expect(
        recordedSegments(segments.expand((s) => s).toList()),
        hasLength(3),
      );
    },
  );
  test(
    'confirmed stop needs consecutive evidence; sparse missing coverage is not dwell',
    () {
      final dense = List.generate(
        11,
        (i) => p(DateTime.utc(2026, 11, 10, 4, 30 + i).toIso8601String()),
      );
      expect(detectedStops(recordedSegments(dense)), hasLength(1));
      expect(
        detectedStops(recordedSegments([dense.first, dense.last])),
        isEmpty,
      );
      expect(
        recordingGaps(recordedSegments([dense.first, dense.last])),
        hasLength(1),
      );
    },
  );
  test('map sampling does not reduce timeline calculation records', () {
    final full = List.generate(
      3000,
      (i) => p(
        DateTime.utc(
          2026,
          11,
          10,
          4,
          30,
        ).add(Duration(seconds: i)).toIso8601String(),
        lat: 23 + i / 1000000,
      ),
    );
    final segments = recordedSegments(full);
    expect(segments.expand((s) => s).length, 3000);
    expect(
      routePreview(segments).expand((s) => s).length,
      lessThanOrEqualTo(1200),
    );
    expect(segments.expand((s) => s).length, 3000);
  });
}
