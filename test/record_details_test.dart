import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/workspace.dart';
import 'package:fieldforce_hrms/trackyu/record_details.dart';
import 'trackyu_integration_test.dart' show Adapter, reply, MemoryVault;

void main() {
  test('legacy leave codes have employee-readable names', () {
    expect(leavePortionLabel('H1'), 'First half');
    expect(leavePortionLabel('H2'), 'Second half');
    expect(leavePortionLabel('FullDay'), 'Full day');
    expect(recordStatus('0'), 'Pending');
  });
  testWidgets('structured details fit a small screen and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RecordDetails(
                fields: {
                  'Reason':
                      'A long reason that should wrap correctly without hiding or cutting the employee details.',
                  'From': '7 Nov 2026',
                  'To': '8 Nov 2026',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reason'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'leave screen shows one readable first-half request without existing label',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('DESIGN_PREVIEWS')) {
        await tester.runAsync(() async {
          for (final pair in [
            ('Roboto', 'roboto-regular.ttf'),
            ('MaterialIcons', 'materialicons-regular.otf'),
          ]) {
            final loader = FontLoader(pair.$1)
              ..addFont(
                File(
                  '../.tools/flutter/bin/cache/artifacts/material_fonts/${pair.$2}',
                ).readAsBytes().then((v) => ByteData.sublistView(v)),
              );
            await loader.load();
          }
        });
      }
      final session = TrackyuController(
        TrackyuApi(
          'https://workspace.test/api',
          client: Dio()
            ..httpClientAdapter = Adapter((r) {
              if (r.path == 'Portal/profile') {
                return reply({'mode': 'Field', 'offices': []});
              }
              if (r.path == 'OfficeLeave/mine') {
                return reply([
                  {
                    'id': 9,
                    'userId': 'QA1',
                    'portion': 'FirstHalf',
                    'status': 'Pending',
                    'fromDate': '2026-11-07',
                    'toDate': '2026-11-07',
                    'reasonName': 'Personal',
                    'reason': 'Family appointment',
                    'legacyLeaveId': 8,
                  },
                ]);
              }
              return reply([]);
            }),
        ),
        vault: MemoryVault(),
      )..user = {'SM_USER_ID': 'QA1', 'NAME': 'QA Employee'};
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'Roboto',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff1c6799),
              ),
              scaffoldBackgroundColor: const Color(0xfff3f6fb),
            ),
            home: WorkspacePage(
              controller: session,
              feature: WorkFeature.leave,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First half leave'), findsOneWidget);
      expect(find.textContaining('Existing leave'), findsNothing);
      expect(find.text('H1'), findsNothing);
      expect(find.byType(RecordDetails), findsOneWidget);
      expect(find.text('Family appointment'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('DESIGN_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../.tools/qa/details-leave.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
