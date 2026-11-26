import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'session_race_test.dart' show TestVault, TestAdapter, jsonReply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => DutyTracker.platformOverride = false);
  TrackyuController make(Future<ResponseBody> Function(RequestOptions) reply) {
    final api = TrackyuApi('https://qa.example/api',
        client: Dio()..httpClientAdapter = TestAdapter(reply),
        deviceIdentity: () async => {'deviceId': 'android:original-phone'});
    api.authorize('token-A');
    return TrackyuController(api, vault: TestVault())
      ..user = {'userId': 'A'}
      ..stateKnown = true
      ..isField = true
      ..offline = true;
  }

  test('invalid session blocks offline punch before selfie or GPS', () async {
    final c = make((_) async => jsonReply(null, status: 401,
        success: false, code: 'DEVICE_SESSION_INVALID'));
    addTearDown(c.dispose);
    await expectLater(c.punch(), throwsA(isA<ApiFailure>()));
    expect(c.pendingPunches, isEmpty);
    expect(c.api.sessionRejected, isTrue);
    expect(c.loggedIn, isTrue);
    await expectLater(c.recordOfflinePunch(), throwsA(isA<ApiFailure>()));
  });

  for (final status in [400, 401, 403, 404, 409, 422, 429, 503]) {
    test('HTTP $status retains pending punch and photo', () async {
      final c = make((_) async => jsonReply(null, status: status,
          success: false, code: 'REJECTED'));
      addTearDown(c.dispose);
      c.pendingPunches.add({'payload': {'selfieBase64': 'retained-photo'}});
      await c.syncPendingPunches();
      expect(c.pendingPunches.single['payload']['selfieBase64'], 'retained-photo');
    });
  }

  test('health success cannot unlock rejection; verified profile can', () async {
    var reject = true;
    final c = make((options) async => reject && options.path != 'Health'
        ? jsonReply(null, status: 401, success: false, code: 'DEVICE_SESSION_INVALID')
        : jsonReply({}));
    addTearDown(c.dispose);
    await expectLater(c.api.verifyPunchAccess(), throwsA(isA<ApiFailure>()));
    await c.api.request('Health');
    expect(c.api.sessionRejected, isTrue);
    reject = false;
    await c.api.verifyPunchAccess();
    expect(c.api.sessionRejected, isFalse);
    expect(c.loggedIn, isTrue);
  });

  test('transport outage permits offline access unless already rejected', () async {
    final c = make((options) async => throw DioException(
        requestOptions: options, type: DioExceptionType.connectionError));
    addTearDown(c.dispose);
    await c.api.verifyPunchAccess();
    c.api.sessionRejected = true;
    await expectLater(c.api.verifyPunchAccess(), throwsA(isA<ApiFailure>()));
  });

  test('late 401 from old account cannot block current account', () async {
    final entered = Completer<void>(), release = Completer<ResponseBody>();
    final c = make((_) { entered.complete(); return release.future; });
    addTearDown(c.dispose);
    final result = expectLater(c.api.request('Employee/my-profile'), throwsA(isA<ApiFailure>()));
    await entered.future;
    c.api.authorize('token-B');
    c.user = {'userId': 'B'};
    release.complete(jsonReply(null, status: 401, success: false, code: 'DEVICE_SESSION_INVALID'));
    await result;
    expect(c.api.sessionRejected, isFalse);
  });

  test('concurrent sync sends once and late receipt cannot modify new account', () async {
    final entered = Completer<void>(), release = Completer<ResponseBody>();
    var calls = 0;
    final c = make((_) { calls++; entered.complete(); return release.future; });
    addTearDown(c.dispose);
    c.pendingPunches.add({'payload': {'selfieBase64': 'photo'}});
    final sync = c.syncPendingPunches();
    await entered.future;
    await c.syncPendingPunches();
    expect(calls, 1);
    c.api.authorize('token-B');
    c.user = {'userId': 'B'};
    release.complete(jsonReply({'id': 99}));
    await sync;
    expect(c.attendance, isNull);
    expect(c.pendingPunches, hasLength(1));
  });
}
