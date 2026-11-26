import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/visit_reconciliation.dart';

void main() {
  group('Visit Reconciliation & Multi-Key Matching', () {
    test('sameVisit matches by retailerId and workDate when numeric ID differs', () {
      final localVisit = {
        'localId': 1732456789,
        'retailerId': 'RET1001',
        'shopName': 's b marketing',
        'workDate': '2026-11-24',
        'checkInUtc': '2026-11-24T06:22:00Z',
        'checkOutUtc': null,
      };

      final serverVisit = {
        'id': 437,
        'retailerId': 'RET1001',
        'shopName': 's b marketing',
        'workDate': '2026-11-24',
        'checkInUtc': '2026-11-24T06:22:00Z',
        'checkOutUtc': '2026-11-24T07:59:00Z',
      };

      expect(sameVisit(localVisit, serverVisit), isTrue);
    });

    test('sameVisit matches by closeRequestId', () {
      final local = {
        'id': 437,
        'closeRequestId': 'close-uuid-1234',
        'checkOutUtc': '2026-11-24T07:59:00Z',
      };

      final server = {
        'id': 437,
        'closeRequestId': 'close-uuid-1234',
        'checkOutUtc': '2026-11-24T07:59:00Z',
      };

      expect(sameVisit(local, server), isTrue);
    });

    test('visitClosed detects non-null checkOutUtc, CheckOutUtc, outUtc, and checkoutUtc', () {
      expect(visitClosed({'checkOutUtc': '2026-11-24T07:59:00Z'}), isTrue);
      expect(visitClosed({'CheckOutUtc': '2026-11-24T07:59:00Z'}), isTrue);
      expect(visitClosed({'outUtc': '2026-11-24T07:59:00Z'}), isTrue);
      expect(visitClosed({'checkoutUtc': '2026-11-24T07:59:00Z'}), isTrue);
      expect(visitClosed({'checkOutUtc': null}), isFalse);
      expect(visitClosed({'checkOutUtc': ''}), isFalse);
      expect(visitClosed({'checkOutUtc': 'null'}), isFalse);
    });

    test('mergePendingVisits ensures server checkout overrides open local snapshot', () {
      final remote = [
        {
          'id': 437,
          'shopName': 's b marketing',
          'workDate': '2026-11-24',
          'checkInUtc': '2026-11-24T06:22:00Z',
          'checkOutUtc': '2026-11-24T07:59:00Z',
        }
      ];

      final local = [
        {
          'localId': 1732456789,
          'shopName': 's b marketing',
          'workDate': '2026-11-24',
          'checkInUtc': '2026-11-24T06:22:00Z',
          'checkOutUtc': null,
          'syncState': 'pending',
        }
      ];

      final merged = mergePendingVisits(remote, local);
      expect(merged.length, equals(1));
      expect(merged[0]['id'], equals(437));
      expect(visitClosed(merged[0]), isTrue);
      expect(merged[0]['checkOutUtc'], equals('2026-11-24T07:59:00Z'));
      expect(merged[0]['syncState'], equals('synced'));
      expect(merged[0]['isOffline'], isFalse);
    });
  });
}
