import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/local_workspace.dart';
import 'local_workspace_test.dart' show MemoryWorkspace;
import 'trackyu_integration_test.dart' show MemoryVault, Adapter, reply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TrackyuController make(
    MemoryWorkspace store, {
    bool fail = false,
    List<String>? dates,
  }) {
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) {
        if (r.path.contains('DutyTracking/day')) {
          final day = '${(r.data as Map)['date']}';
          dates?.add(day);
          expect((r.data as Map)['includeRaw'], true);
          if (fail) return reply({}, status: 503, success: false);
          return reply({
            'date': day,
            'userId': 'worker',
            'recordedPoints': [],
            'events': [],
            'visits': [],
            'attendance': [
              {
                'id': day,
                'punchInUtc': '${day}T04:30:00Z',
                'punchOutUtc': '${day}T12:30:00Z',
              },
            ],
          });
        }
        if (r.path.contains('MobileVisits/mine')) {
          expect(
            r.uri.queryParameters['date'],
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
          );
          return reply([]);
        }
        if (r.path.endsWith('Portal/profile'))
          return reply({'mode': 'Field', 'offices': []});
        return reply([]);
      });
    return TrackyuController(
        TrackyuApi('https://test.example/api', client: dio),
        vault: MemoryVault(),
      )
      ..user = {'userId': 'worker'}
      ..local = store
      ..stateKnown = true
      ..isField = true;
  }

  test(
    'seven concurrent date restores have distinct readable keys; malformed key is retained',
    () async {
      final store = MemoryWorkspace();
      store.records['day:'] = {'untrusted': 'leave unchanged'};
      final dates = <String>[];
      final c = make(store, dates: dates);
      addTearDown(c.dispose);
      expect(await c.restoreDataFromServer(), true);
      expect(dates.toSet(), hasLength(7));
      for (final day in dates) {
        final row = await store.read('day:$day');
        expect(row!['report']['date'], day);
        expect(row['attendance']['punchInUtc'], '${day}T04:30:00Z');
      }
      final yesterday = LocalWorkspace.day(
        DateTime.parse(c.localDay).subtract(const Duration(days: 1)),
      );
      expect((await c.localDayData(yesterday))['report']['date'], yesterday);
      expect(store.records['day:'], {'untrusted': 'leave unchanged'});
      expect(c.notice, startsWith('7 daily timelines restored.'));
    },
  );
  test(
    'local finished attendance and rich visits survive a stale open server copy',
    () async {
      final store = MemoryWorkspace();
      final c = make(store);
      addTearDown(c.dispose);
      store.records[c.dayKey] = {
        'attendance': {
          'id': c.localDay,
          'punchInUtc': '${c.localDay}T04:30:00Z',
          'punchOutUtc': '${c.localDay}T13:00:00Z',
        },
        'visits': [
          {
            'id': 7,
            'checkInUtc': '${c.localDay}T05:00:00Z',
            'checkOutUtc': '${c.localDay}T06:00:00Z',
            'address': 'Preserve me',
          },
        ],
      };
      expect(await c.restoreDataFromServer(), true);
      final day = await c.localDayData();
      expect(day['visits'].single['address'], 'Preserve me');
      expect(day['attendance']['punchOutUtc'], isNotNull);
    },
  );
  test(
    'failed daily downloads are not reported as successful restore',
    () async {
      final store = MemoryWorkspace();
      store.records['day:known'] = {'kept': true};
      final c = make(store, fail: true);
      addTearDown(c.dispose);
      expect(await c.restoreDataFromServer(), false);
      expect(c.notice, contains('Restored 0 of 7'));
      expect(c.notice, contains('failed'));
      expect(store.records['day:known'], {'kept': true});
    },
  );
  test(
    'pending operations prevent restore without changing local records',
    () async {
      final store = MemoryWorkspace();
      store.operations.add({'id': 'pending'});
      store.records['day:saved'] = {'kept': true};
      final dates = <String>[];
      final c = make(store, dates: dates);
      addTearDown(c.dispose);
      expect(await c.restoreDataFromServer(), false);
      expect(dates, isEmpty);
      expect(store.operations.single['id'], 'pending');
      expect(store.records['day:saved'], {'kept': true});
    },
  );
}
