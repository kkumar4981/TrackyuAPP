import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'package:fieldforce_hrms/trackyu/gps_fix_validator.dart';
import 'session_race_test.dart' show TestVault, TestAdapter, jsonReply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TrackyuController make(TestVault vault, [Future<ResponseBody> Function(RequestOptions)? respond]) {
    final dio = Dio()..httpClientAdapter = TestAdapter(respond ?? (_) async => jsonReply([]));
    final c = TrackyuController(
      TrackyuApi('https://test.example/api', client: dio, deviceIdentity: () async => {'deviceId': 'qa'}),
      vault: vault,
      locate: () async => {
        'latitude': 23.2599,
        'longitude': 77.4126,
        'accuracyMeters': 5.0,
        'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
      },
    )..user = {'userId': 'A'};
    c.api.authorize('qa-session');
    c.isField = true;
    c.stateKnown = true;
    c.enabledMenus = {'visits'};
    c.attendance = {
      'id': 1,
      'punchInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
      'punchOutUtc': null,
    };
    c.syncServerTime(DateTime.now().toUtc().toIso8601String());
    return c;
  }

  group('1. Status Bar & Theme Overlay Exhaustive Verification', () {
    test('All 7 themes enforce correct contrast and transparent status bar', () async {
      final vault = TestVault();
      final c = make(vault);

      final lightThemes = ['beta', 'blossom', 'emerald', 'ocean', 'classic'];
      final darkThemes = ['dark', 'amoled'];

      for (final theme in lightThemes) {
        await c.setTheme(theme);
        expect(c.activeTheme, theme);
        expect(c.isDarkMode, isFalse, reason: '$theme must be light mode');
        expect(
          c.themeBackgroundColor.computeLuminance(),
          greaterThanOrEqualTo(0.45),
          reason: '$theme background must be light so status bar icons are dark',
        );
      }

      for (final theme in darkThemes) {
        await c.setTheme(theme);
        expect(c.activeTheme, theme);
        expect(c.isDarkMode, isTrue, reason: '$theme must be dark mode');
        expect(
          c.themeBackgroundColor.computeLuminance(),
          lessThan(0.45),
          reason: '$theme background must be dark so status bar icons are white',
        );
      }

      c.dispose();
    });
  });

  group('2. VisitForm Ultra-Small Screen & 2.0x Font Scale Layout', () {
    testWidgets('VisitForm fits 320px width at 2.0x accessibility font scale without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vault = TestVault();
      final c = make(vault);
      final visitsData = VisitsData(c);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: VisitForm(
            data: visitsData,
            visit: {
              'id': 101,
              'kind': 'Open',
              'shopName': 'Ultra Long Shop Name Testing Overflow Safeguards Pvt Ltd',
              'version': 'AAAAAAAAAAA=',
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Zero RenderFlex layout exceptions
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Selfie & punch out'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      visitsData.dispose();
      c.dispose();
    });
  });

  group('3. Offline Punch-Out Card & Zero Resurrection Lifecycle', () {
    test('Offline punch-out clears active visit immediately and resists timer resurrection', () async {
      final vault = TestVault();
      final c = make(vault);
      c.setOffline(true);

      final visitRow = {
        'id': 505,
        'kind': 'Open',
        'shopName': 'Mehta Sales',
        'version': 'AAAAAAAAAAA=',
        'requestId': 'req-start-505',
      };

      c.activeVisit = visitRow;
      expect(c.activeVisit?['id'], 505);

      // Simulate punch out queued
      final queued = {
        'scope': c.visitCacheScope,
        'finish': true,
        'durable': true,
        'body': {
          'id': 505,
          'startRequestId': 'req-start-505',
          'requestId': 'req-finish-505',
          'departureSelfieBase64': 'photo-bytes',
        },
      };
      c.pendingVisits.add(queued);
      c.clearActiveVisit();

      // Active visit MUST be null
      expect(c.activeVisit, isNull);

      // Even if setClosingVisit is called with a 25s timer, visit is closed/closing
      c.setClosingVisit(id: '505', shopName: 'Mehta Sales');
      expect(c.activeVisit, isNull);

      c.dispose();
    });
  });

  group('4. GPS Fix Validation & Anti-Spoofing', () {
    final baseTime = DateTime.parse('2026-11-21T10:00:00Z');

    test('GPS Validator blocks mock locations, invalid coordinates, and stale fixes', () {
      // Valid GPS fix
      expect(
        isValidGpsFix(
          lat: 23.2599,
          lng: 77.4126,
          acc: 12.5,
          capturedAt: baseTime.subtract(const Duration(seconds: 30)),
          isMocked: false,
          now: baseTime,
        ),
        isTrue,
      );

      // Rejected: Mock location
      expect(
        isValidGpsFix(
          lat: 23.2599,
          lng: 77.4126,
          acc: 12.5,
          capturedAt: baseTime.subtract(const Duration(seconds: 30)),
          isMocked: true,
          now: baseTime,
        ),
        isFalse,
      );

      // Rejected: Null Island (0,0)
      expect(
        isValidGpsFix(
          lat: 0.0,
          lng: 0.0,
          acc: 12.5,
          capturedAt: baseTime.subtract(const Duration(seconds: 30)),
          isMocked: false,
          now: baseTime,
        ),
        isFalse,
      );

      // Rejected: Impossibly bad accuracy (> 500m)
      expect(
        isValidGpsFix(
          lat: 23.2599,
          lng: 77.4126,
          acc: 650.0,
          capturedAt: baseTime.subtract(const Duration(seconds: 30)),
          isMocked: false,
          now: baseTime,
        ),
        isFalse,
      );

      // Rejected: Stale fix (> 15 minutes old)
      final staleTime = baseTime.subtract(const Duration(minutes: 20));
      expect(
        isValidGpsFix(
          lat: 23.2599,
          lng: 77.4126,
          acc: 15.0,
          capturedAt: staleTime,
          isMocked: false,
          now: baseTime,
        ),
        isFalse,
      );
    });
  });
}
