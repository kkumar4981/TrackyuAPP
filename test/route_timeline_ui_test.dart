import 'dart:async';
import 'package:flutter/services.dart';
import 'package:fieldforce_hrms/trackyu/duty_tracking.dart';
import 'package:fieldforce_hrms/trackyu/timeline_reconciliation.dart';
import 'local_workspace_test.dart' show MemoryWorkspace;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/tracking_status.dart';
import 'trackyu_integration_test.dart' show Adapter, reply, MemoryVault;

void main() {
  testWidgets('slow GPS does not hide attendance or block the timeline', (
    tester,
  ) async {
    DutyTracker.platformOverride = true;
    addTearDown(() => DutyTracker.platformOverride = null);
    final gate = Completer<List<dynamic>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DutyTracker.channel, (call) async {
          if (call.method == 'route') return gate.future;
          return <String, dynamic>{};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DutyTracker.channel, null),
    );
    final controller = TrackyuController(
      TrackyuApi('https://test.example/api'),
      vault: MemoryVault(),
    )..user = {'SM_USER_ID': 'TEST'};
    controller.local = MemoryWorkspace({
      'events': [
        {
          'type': 'PunchIn',
          'atUtc': '${businessDay(DateTime.now())}T05:00:00Z',
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(home: DutyRoutePage(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Punch-in'), findsWidgets);
    expect(find.text('Loading timeline...'), findsNothing);
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(find.text('Punch-in'), findsWidgets);
    expect(find.textContaining('Unable to read phone data'), findsNothing);
    expect(tester.takeException(), isNull);
    gate.complete([]);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'route timeline fits a narrow screen and uses friendly attendance labels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (r) => reply({
            'route': {'segments': [], 'stops': []},
            'events': [
              {
                'type': 'PunchIn',
                'title': 'Duty punch-in',
                'atUtc': '${businessDay(DateTime.now())}T05:00:00Z',
              },
              {
                'type': 'PunchOut',
                'title': 'Duty punch-out',
                'atUtc': '${businessDay(DateTime.now())}T05:30:00Z',
              },
            ],
          }),
        );
      final controller = TrackyuController(
        TrackyuApi('https://test.example/api', client: dio),
        vault: MemoryVault(),
      );
      controller.local = MemoryWorkspace(
        Map<String, dynamic>.from(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: DutyRoutePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Punch-out'), 150);
      expect(find.text('Punch-out'), findsOneWidget);
      expect(find.textContaining('Duty'), findsNothing);
      expect(find.textContaining('PunchOut -'), findsNothing);
      expect(tester.takeException(), isNull);
      controller.local = MemoryWorkspace(
        Map<String, dynamic>.from(
          (await tester.runAsync(() => controller.api.request('fixture')))
              as Map,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
