import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/visit_reconciliation.dart';

void main() {
  test('pending local ID maps by start request without duplicating a visit', () {
    final rows = mergePendingVisits([
      {'id': 42, 'requestId': 'start-A', 'version': 'server', 'checkOutUtc': null}
    ], [
      {'id': 9000, 'localId': 9000, 'requestId': 'start-A', 'isOffline': true,
        'syncState': 'pending', 'checkOutUtc': '2026-11-20T10:00:00Z', 'departureSelfieBase64': 'retained-photo'}
    ]);
    expect(rows, hasLength(1));
    expect(rows.single['id'], 42);
    expect(rows.single['localId'], 9000);
    expect(rows.single['version'], 'server');
    expect(rows.single['checkOutUtc'], isNotNull);
    expect(rows.single['departureSelfieBase64'], 'retained-photo');
  });

  test('refresh retains every pending checkout, not only one active visit', () {
    final rows = mergePendingVisits([], [
      {'id': 1, 'isOffline': true, 'syncState': 'pending', 'checkOutUtc': 'done', 'selfieBase64': 'in'},
      {'id': 2, 'isOffline': true, 'syncState': 'blocked', 'checkOutUtc': 'done', 'departureSelfieBase64': 'out'},
      {'id': 3, 'isOffline': true, 'syncState': 'pending', 'checkOutUtc': null}
    ]);
    expect(rows, hasLength(3));
    expect(rows[0]['selfieBase64'], 'in');
    expect(rows[1]['departureSelfieBase64'], 'out');
  });

  test('synced server checkout wins over stale active UI row', () {
    final rows = mergePendingVisits([
      {'id': 42, 'checkOutUtc': 'server-closed'}
    ], [
      {'id': 42, 'checkOutUtc': null, 'syncState': 'synced', 'isOffline': true}
    ]);
    expect(rows.single['checkOutUtc'], 'server-closed');
  });

  test('explicit checkout never selects a different open shop', () {
    final rows = <VisitRecord>[
      {'id': 1, 'checkOutUtc': null},
      {'id': 2, 'localId': 222, 'checkOutUtc': null},
    ];
    expect(checkoutVisitIndex(rows, 2), 1);
    expect(checkoutVisitIndex(rows, 222), 1);
    expect(checkoutVisitIndex(rows, 999), -1);
    expect(checkoutVisitIndex(rows, null), -1);
  });

  test('merge does not mutate the durable source records', () {
    final local = <VisitRecord>[{'id': 9000, 'requestId': 'A', 'isOffline': true}];
    final remote = <VisitRecord>[{'id': 42, 'requestId': 'A'}];
    mergePendingVisits(remote, local);
    expect(local.single['id'], 9000);
    expect(remote.single['id'], 42);
  });
}
