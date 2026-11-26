import 'dart:async';
import 'package:dio/dio.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'trackyu_integration_test.dart' show reply;

class AsyncAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handle;
  AsyncAdapter(this.handle);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late TrackyuApi api;
  late Completer<Map<String, dynamic>> leaseCompleter;

  setUp(() {
    DutyTracker.platformOverride = true;
    calls = [];
    leaseCompleter = Completer<Map<String, dynamic>>();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return <String, dynamic>{
          'active': false,
          'userId': 'TEST_USER',
          'baseUrl': 'https://qa.example/api',
        };
      }
      return null;
    });

    final dio = Dio()
      ..httpClientAdapter = AsyncAdapter((r) async {
        if (r.path.contains('DutyTracking/lease')) {
          final data = await leaseCompleter.future;
          return reply(data);
        }
        return reply({});
      });

    api = TrackyuApi(
      'https://qa.example/api',
      client: dio,
      deviceIdentity: () async => {'deviceId': 'test-device-id'},
    );
  });

  tearDown(() {
    DutyTracker.platformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, null);
  });

  test('A-12: Stale asynchronous reconcile cannot restart tracking after punch-out', () async {
    // 1. Employee was on duty, so reconcile starts with active=true (punchOutUtc is null)
    final reconcileFuture = DutyTracker.reconcile(
      api,
      'Field',
      {'id': 101, 'punchOutUtc': null},
      userId: 'TEST_USER',
    );

    // Give time for reconcile to reach the lease await
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 2. While lease is in flight, employee punches out!
    // stop() is invoked, which increments the generation counter.
    await DutyTracker.stop();
    expect(calls.where((c) => c.method == 'stop').isNotEmpty, isTrue);

    // 3. Now the delayed lease response arrives from the server
    leaseCompleter.complete({
      'userId': 'TEST_USER',
      'trackingKey': 'sample-tracking-key-1234567890123456',
      'dutyCutoffUtc': '2099-11-07T17:30:00Z',
      'expiresAtUtc': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
      'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
    });

    await reconcileFuture;

    // 4. VERIFICATION:
    // With generation guard in place, the stale reconcile MUST NOT configure active=true!
    final configureCalls = calls.where((c) => c.method == 'configure').toList();
    expect(configureCalls, isEmpty, reason: 'configure must not be called after punch-out occurred');
  });
}
