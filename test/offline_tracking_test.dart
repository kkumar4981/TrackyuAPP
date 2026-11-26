import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'trackyu_integration_test.dart' show Adapter, MemoryVault, reply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('offline attendance is blocked while confirmed cached duty is retained', () async {
    final vault = MemoryVault();
    final now = DateTime.now().toUtc();
    final token = 'x.${base64UrlEncode(utf8.encode(jsonEncode({'exp': now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})))}.x';
    vault.value = jsonEncode({'server': 'https://qa.example/api', 'token': token,
      'user': {'SM_USER_ID': 'QA'}, 'attendanceCache': {'isField': true,
      'workDate': now.toLocal().toIso8601String().split('T').first,
      'attendance': {'id': 77, 'punchInUtc': now.subtract(const Duration(minutes: 30)).toIso8601String()}}});
    final dio = Dio()..httpClientAdapter = Adapter((r) => throw DioException(requestOptions: r, type: DioExceptionType.connectionError));
    final c = TrackyuController(TrackyuApi('https://qa.example/api', client: dio,
      deviceIdentity: () async => {'deviceId': 'android:offline-qa-device'}), vault: vault);
    await c.initialize();
    await expectLater(c.punch(), throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'SERVER_REQUIRED')));
    expect(c.loggedIn, isTrue); expect(c.attendance?['id'], 77);
    expect(c.attendance?['punchOutUtc'], isNull); expect(c.pendingPunches, isEmpty);
    c.dispose();
  });

  test(
    'stale cached attendance does not resurrect previous duty while offline',
    () async {
      final vault = MemoryVault();
      final token =
          'x.${base64UrlEncode(utf8.encode(jsonEncode({'exp': DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000})))}.x';
      // Yesterday's punch
      final yesterdayUtc = DateTime.now().toUtc().subtract(const Duration(days: 1, hours: 2));
      vault.value = jsonEncode({
        'server': 'https://qa.example/api',
        'token': token,
        'user': {'SM_USER_ID': 'QA_DAY_CHANGE'},
        'attendanceCache': {
          'isField': true,
          'workDate': '2026-11-01',
          'attendance': {
            'id': 99,
            'punchInUtc': yesterdayUtc.toIso8601String(),
            'punchOutUtc': null,
          },
        },
      });

      final dio = Dio()..httpClientAdapter = Adapter((r) => throw DioException(requestOptions: r, type: DioExceptionType.connectionError));
      final c = TrackyuController(
        TrackyuApi('https://qa.example/api', client: dio, deviceIdentity: () async => {'deviceId': 'test-phone'}),
        vault: vault,
        locate: () async => {'latitude': 28.5, 'longitude': 77.1, 'accuracyMeters': 5.0, 'capturedAtUtc': DateTime.now().toUtc().toIso8601String()},
      );

      await c.initialize();
      expect(c.offline, isTrue);
      // Historical cached attendance must not be shown as today's active duty.
      // Server/native cutoff handling owns closing historical sessions.
      expect(c.onDuty, isFalse);
      expect(c.attendance, isNull);
      expect(c.loggedIn, isTrue);
      c.dispose();
    },
  );

  test(
    'offline signOut cannot fabricate attendance or lose the active session',
    () async {
      final vault = MemoryVault();
      final token =
          'x.${base64UrlEncode(utf8.encode(jsonEncode({'exp': DateTime.now().add(const Duration(hours: 4)).millisecondsSinceEpoch ~/ 1000})))}.x';
      vault.value = jsonEncode({
        'server': 'https://qa.example/api',
        'token': token,
        'user': {'SM_USER_ID': 'QA_LOGOUT'},
        'attendanceCache': {
          'isField': true,
          'workDate': DateTime.now().toLocal().toIso8601String().split('T').first,
          'attendance': {
            'id': 105,
            'punchInUtc': DateTime.now().toUtc().subtract(const Duration(minutes: 30)).toIso8601String(),
            'punchOutUtc': null,
          },
        },
      });

      final dio = Dio()..httpClientAdapter = Adapter((r) => throw DioException(requestOptions: r, type: DioExceptionType.connectionError));
      final c = TrackyuController(
        TrackyuApi('https://qa.example/api', client: dio, deviceIdentity: () async => {'deviceId': 'test-phone'}),
        vault: vault,
        locate: () async => {'latitude': 28.5, 'longitude': 77.1, 'accuracyMeters': 5.0, 'capturedAtUtc': DateTime.now().toUtc().toIso8601String()},
      );

      await c.initialize();
      expect(c.onDuty, isTrue);
      await expectLater(c.signOut(autoPunchOut: true), throwsA(isA<ApiFailure>()));
      expect(c.loggedIn, isTrue);
      expect(c.attendance?['punchOutUtc'], isNull);
      expect(c.pendingPunches, isEmpty);
      c.dispose();
    },
  );
}
