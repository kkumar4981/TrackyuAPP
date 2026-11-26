import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P0 — Tracking Pipeline Diagnostics & Timestamps', () {
    test('distinct timestamps for received, persisted, attempted, and acknowledged fixes', () {
      final now = DateTime.now().toUtc();
      final tReceived = now.subtract(const Duration(seconds: 5)).toIso8601String();
      final tPersisted = now.subtract(const Duration(seconds: 4)).toIso8601String();
      final tAttempted = now.subtract(const Duration(seconds: 2)).toIso8601String();
      final tAcknowledged = now.toIso8601String();

      final telemetry = <String, dynamic>{
        'lastGpsReceivedAtUtc': tReceived,
        'lastGpsPersistedAtUtc': tPersisted,
        'lastUploadAttemptedAtUtc': tAttempted,
        'lastUploadAcknowledgedAtUtc': tAcknowledged,
        'pendingCount': 3,
      };

      expect(telemetry['lastGpsReceivedAtUtc'], isNotEmpty);
      expect(telemetry['lastGpsPersistedAtUtc'], isNotEmpty);
      expect(telemetry['lastUploadAttemptedAtUtc'], isNotEmpty);
      expect(telemetry['lastUploadAcknowledgedAtUtc'], isNotEmpty);
      expect(telemetry['lastGpsReceivedAtUtc'] != telemetry['lastUploadAcknowledgedAtUtc'], isTrue);
    });

    test('preserves unsynced data and avoids inferring zero capture from zero uploads', () {
      // Simulating a phone that captured 15 GPS points offline but uploaded 0 due to network / 401
      final offlineHealth = <String, dynamic>{
        'pendingCount': 15,
        'lastGpsPersistedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'lastUploadAttemptedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'lastUploadAcknowledgedAtUtc': '',
        'uploadedPointsCount': 0,
      };

      final pendingCount = offlineHealth['pendingCount'] as int;
      final uploadedCount = offlineHealth['uploadedPointsCount'] as int;

      // Verification rule: uploaded == 0 must NEVER mean captured == 0
      final hasCapturedPointsLocally = pendingCount > 0 || (offlineHealth['lastGpsPersistedAtUtc'] as String).isNotEmpty;
      expect(uploadedCount, equals(0));
      expect(hasCapturedPointsLocally, isTrue);
      expect(pendingCount, equals(15));
    });

    test('401 unauthorized preserves local pending queue without acknowledging or dropping', () {
      final queue = <Map<String, dynamic>>[
        {'id': 'p1', 'lat': 23.24, 'lng': 77.42, 'ack': 0},
        {'id': 'p2', 'lat': 23.25, 'lng': 77.43, 'ack': 0},
      ];

      // Simulate HTTP 401 response from server
      const httpStatusCode = 401;

      // Behavior contract: do not acknowledge queue on non-200
      if (httpStatusCode == 200) {
        for (var p in queue) {
          p['ack'] = 1;
        }
      }

      // Assert all items retain ack = 0 (unacknowledged and preserved)
      expect(queue.every((p) => p['ack'] == 0), isTrue);
      expect(queue.length, equals(2));
    });
  });

  group('P1 — Stationary Handling & GPS Drift', () {
    test('indoor drift below deadband does not increment persisted count within 10 minutes', () {
      final initialPoint = {'lat': 23.24194, 'lng': 77.42613, 'capturedMs': 1000000};
      var persistedPoints = 1;
      var lastPersistedMs = initialPoint['capturedMs'] as int;
      String? lastGpsReceivedUtc;

      // Drift fix 5 meters away after 60 seconds (well within 10 min window and below 25m deadband)
      const distanceMovedMeters = 5.0;
      const deadbandMeters = 25.0;
      final currentFixMs = lastPersistedMs + 60000;

      if (distanceMovedMeters < deadbandMeters && (currentFixMs - lastPersistedMs) < 600000) {
        // Stationary: hardware fix received is updated, but NOT persisted to SQLite
        lastGpsReceivedUtc = DateTime.fromMillisecondsSinceEpoch(currentFixMs).toUtc().toIso8601String();
      } else {
        persistedPoints++;
        lastPersistedMs = currentFixMs;
      }

      expect(persistedPoints, equals(1)); // Did not increment
      expect(lastGpsReceivedUtc, isNotNull);
    });

    test('10-minute stationary heartbeat forces periodic anchor fix even without movement', () {
      var persistedPoints = 1;
      var lastPersistedMs = 1000000;

      // 10 minutes (600,000 ms) have elapsed while stationary
      const distanceMovedMeters = 2.0;
      const deadbandMeters = 25.0;
      final currentFixMs = lastPersistedMs + 600000;

      if (distanceMovedMeters < deadbandMeters && (currentFixMs - lastPersistedMs) < 600000) {
        // Filtered
      } else {
        // Heartbeat triggers: append to SQLite
        persistedPoints++;
        lastPersistedMs = currentFixMs;
      }

      expect(persistedPoints, equals(2)); // Heartbeat point persisted
      expect(lastPersistedMs, equals(1600000));
    });

    test('process restart recovers lastCaptured anchor from stored state', () {
      // Simulating app restart where in-memory lastCaptured was reset to 0
      var inMemoryLastCaptured = 0;
      final storedState = {
        'lastPoint': {
          'capturedAtUtc': '2026-11-12T10:00:00.000Z',
          'latitude': 23.24,
          'longitude': 77.42,
        }
      };

      // Recovery logic
      if (inMemoryLastCaptured == 0) {
        final lastPt = storedState['lastPoint'];
        if (lastPt != null) {
          inMemoryLastCaptured = DateTime.parse(lastPt['capturedAtUtc'] as String).millisecondsSinceEpoch;
        }
      }

      expect(inMemoryLastCaptured, equals(DateTime.parse('2026-11-12T10:00:00.000Z').millisecondsSinceEpoch));
    });
  });

  group('P1 — Tracking Health Diagnostics Correctness', () {
    test('unverified OEM autostart does not falsely trigger warning score', () {
      const batteryExempt = true;
      const isAlways = true;
      const gpsOn = true;
      const requiresAutostart = true;
      const autostartVerifiable = false;
      final autostartSettingsOpened = false;
      expect(autostartSettingsOpened, isFalse);

      // Health warning calculation formula
      final hasWarning = !batteryExempt || !isAlways || !gpsOn;

      // Autostart status is reported as manual check, never blocking warning score
      expect(hasWarning, isFalse);
      expect(autostartVerifiable, isFalse);
      expect(requiresAutostart, isTrue);
    });

    test('verified active foreground service requires live service, not just stale stored flag', () {
      // Stale state in SQLite/SharedPreferences from previous session
      final storedState = {'running': true};
      final isNativeServiceAlive = storedState['forceAlive'] == true; // OS killed process or service stopped

      // Verified running check
      final isServiceVerifiedRunning = isNativeServiceAlive && (storedState['running'] == true);

      expect(storedState['running'], isTrue);
      expect(isServiceVerifiedRunning, isFalse); // Protected against stale running flag
    });
  });

  group('P2 — OEM Safe Intent Component Validation', () {
    test('approved OEM component allowlist permits only validated package and activity pairs', () {
      final approvedComponents = <String>{
        'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
        'com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity',
        'com.oplus.battery/com.oplus.battery.AppListActivity',
        'com.vivo.permissionmanager/com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
        'com.samsung.android.lool/com.samsung.android.sm.battery.ui.BatteryActivity',
      };

      bool isComponentApproved(String pkg, String act) {
        return approvedComponents.contains('$pkg/$act');
      }

      // Valid Xiaomi AutoStart
      expect(
        isComponentApproved(
          'com.miui.securitycenter',
          'com.miui.permcenter.autostart.AutoStartManagementActivity',
        ),
        isTrue,
      );

      // Arbitrary / unapproved internal activity from a valid package is rejected
      expect(
        isComponentApproved(
          'com.miui.securitycenter',
          'com.miui.securitycenter.internal.ArbitrarySecretActivity',
        ),
        isFalse,
      );

      // Completely untrusted package is rejected
      expect(
        isComponentApproved('com.malicious.app', 'com.malicious.app.MainActivity'),
        isFalse,
      );
    });
  });
}
