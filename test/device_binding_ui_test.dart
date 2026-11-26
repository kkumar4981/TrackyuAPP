import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/app.dart';
import 'trackyu_integration_test.dart' show MemoryVault, Adapter, reply;

void main() {
  testWidgets(
    'blocked phone requests admin approval without saving password or granting a session',
    (tester) async {
      final vault = MemoryVault();
      final calls = <RequestOptions>[];
      var approved = false;
      final dio = Dio()
        ..httpClientAdapter = Adapter((request) {
          calls.add(request);
          if (request.path == 'Auth/login') {
            return reply(
              null,
              status: 403,
              success: false,
              code: 'DEVICE_CHANGE_REQUIRED',
            );
          }
          if (request.path == 'DeviceBindings/request-change') {
            return reply({'id': 71, 'status': 'Pending'});
          }
          if (request.path == 'DeviceBindings/request-status') {
            return reply({
              'id': 71,
              'status': approved ? 'Approved' : 'Pending',
            });
          }
          return reply(
            null,
            status: 500,
            success: false,
            code: 'UNEXPECTED_TEST_CALL',
          );
        });
      final api = TrackyuApi(
        'https://test.example/api',
        client: dio,
        deviceIdentity: () async => {
          'deviceId': 'test:replacement-device-01',
          'deviceName': 'New test phone',
        },
      );
      final controller = TrackyuController(api, vault: vault);
      await tester.pumpWidget(
        MaterialApp(home: LegacyLogin(controller: controller)),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'WF1');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'private-password',
      );
      await tester.scrollUntilVisible(
        find.text('Login'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(controller.loggedIn, isFalse);
      expect(vault.value, isNull);
      await tester.scrollUntilVisible(
        find.text('Request device change'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Request device change'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason'),
        'My previous phone was replaced',
      );
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('pending administrator review and approval'),
        findsOneWidget,
      );
      final body =
          calls
                  .firstWhere((r) => r.path == 'DeviceBindings/request-change')
                  .data
              as Map;
      expect(body['deviceId'], 'test:replacement-device-01');
      expect(body['reason'], 'My previous phone was replaced');
      expect(controller.loggedIn, isFalse);
      expect(vault.value, isNull);
      approved = true;
      await tester.scrollUntilVisible(
        find.text('Check request status'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check request status'));
      await tester.pumpAndSettle();
      expect(
        find.text('Device change approved! Please sign in to link this device.'),
        findsOneWidget,
      );
      expect(controller.loggedIn, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
