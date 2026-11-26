import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/readiness.dart';

class ProbeAdapter implements HttpClientAdapter {
  bool slow = true, unavailable = false, timedOut = false;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls++;
    if (timedOut) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    if (slow) await Future<void>.delayed(const Duration(milliseconds: 2100));
    return ResponseBody.fromString(
      '{"success":true}',
      unavailable ? 503 : 200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'measured slow connection is advisory, cached, and manual retry recovers',
    () async {
      final adapter = ProbeAdapter();
      final api = TrackyuApi(
        'https://workspace.test/api',
        client: Dio()..httpClientAdapter = adapter,
      );
      final phone = PhoneReadiness(api);
      final monitor = DeviceReadiness(phone);
      await monitor.refresh();
      expect(monitor.slowConnection, isTrue);
      expect(monitor.ready, isTrue);
      monitor.continueToApp();
      expect(monitor.blocking, isFalse);
      await monitor.refresh();
      expect(adapter.calls, 1);
      adapter.slow = false;
      await monitor.fix(SetupItem.speed);
      expect(monitor.slowConnection, isFalse);
      expect(adapter.calls, 2);
      monitor.dispose();
      api.dio.close();
    },
  );
  test(
    'unreachable server blocks without incorrectly claiming a slow network',
    () async {
      final adapter = ProbeAdapter()
        ..slow = false
        ..unavailable = true;
      final api = TrackyuApi(
        'https://workspace.test/api',
        client: Dio()..httpClientAdapter = adapter,
      );
      final monitor = DeviceReadiness(PhoneReadiness(api));
      await monitor.refresh();
      expect(monitor.ready, isFalse);
      expect(monitor.slowConnection, isFalse);
      expect(
        monitor.checks.firstWhere((c) => c.item == SetupItem.server).ready,
        isFalse,
      );
      monitor.dispose();
      api.dio.close();
    },
  );
  test(
    'timeout warns to reconcile attendance and never replays a write',
    () async {
      final adapter = ProbeAdapter()..timedOut = true;
      final api = TrackyuApi(
        'https://workspace.test/api',
        client: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        api.request('FieldAttendance/punch-in', body: {}),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.code, 'code', 'CONNECTION_TIMEOUT')
              .having(
                (e) => e.message,
                'message',
                contains('Reload attendance'),
              ),
        ),
      );
      expect(adapter.calls, 1);
      api.dio.close();
    },
  );
}
